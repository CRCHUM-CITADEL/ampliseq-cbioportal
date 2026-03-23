#!/usr/bin/env python3.12
"""
Parse a *-basespace-cnv.final.vcf file and write CNA data compatible with cBioPortal.
- Gene name: Hugo Symbol fetched from mygene.info using the ID column (hg19/human)
- Copy number: FORMAT CN field in sample column named Sample
- Only FILTER=PASS records are processed
- CN mapping: 0→-2, 1→-1, 2→0, 3→1, >=4→2
Usage: python3 format_cna_vcf.py <cnv.vcf[.gz]> <Sample_Id>
"""

import sys
import os
import gzip
import json
import urllib.request
import urllib.parse


def copy_number_to_value(cn):
    if cn == 0:
        return -2
    elif cn == 1:
        return -1
    elif cn == 2:
        return 0
    elif cn == 3:
        return 1
    elif cn >= 4:
        return 2
    return None


def fetch_hugo_symbols(gene_ids):
    """Batch-query mygene.info for official Hugo Symbols (human/hg19).

    Sends GET requests using 'symbol:GENE1 OR symbol:GENE2 ...' syntax in
    chunks of 50 to stay within URL length limits.  Returns a dict mapping
    each input gene ID (case-insensitive match) to its canonical symbol.
    IDs not resolved by mygene.info are absent from the result.
    """
    if not gene_ids:
        return {}

    CHUNK = 50
    canonical: dict[str, str] = {}  # upper(symbol) -> canonical symbol

    genes = list(gene_ids)
    for i in range(0, len(genes), CHUNK):
        chunk = genes[i : i + CHUNK]
        q = " OR ".join(f"symbol:{g}" for g in chunk)
        params = urllib.parse.urlencode({
            "q": q,
            "fields": "symbol",
            "species": "human",
            "size": CHUNK,
        })
        url = f"https://mygene.info/v3/query?{params}"
        try:
            with urllib.request.urlopen(url, timeout=30) as resp:
                data = json.loads(resp.read())
            for hit in data.get("hits", []):
                sym = hit.get("symbol", "")
                if sym:
                    canonical[sym.upper()] = sym
        except Exception as e:
            print(f"Warning: mygene.info lookup failed: {e}", file=sys.stderr)

    # Map input IDs → canonical symbol via case-insensitive key
    return {gid: canonical[gid.upper()] for gid in gene_ids if gid.upper() in canonical}


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <cnv.vcf[.gz]> <Sample_Id>", file=sys.stderr)
        sys.exit(1)

    vcf_file, sample_id = sys.argv[1], sys.argv[2]

    opener = gzip.open if vcf_file.endswith('.gz') else open
    records = []   # list of (raw_gene_id, cn_value)
    format_col = 8
    sample_col = 9

    with opener(vcf_file, 'rt') as fh:
        for line in fh:
            if line.startswith('##'):
                continue
            if line.startswith('#CHROM'):
                headers = line.lstrip('#').rstrip('\n').split('\t')
                try:
                    sample_col = next(
                        i for i, h in enumerate(headers)
                        if h.lower() == 'sample'
                    )
                except StopIteration:
                    sample_col = 9
                continue

            parts = line.rstrip('\n').split('\t')
            if len(parts) <= sample_col:
                continue

            if parts[6] != 'PASS':
                continue

            gene_id = parts[2]
            if not gene_id or gene_id == '.':
                continue

            fmt_fields = parts[format_col].split(':')
            smp_fields = parts[sample_col].split(':')

            try:
                cn_idx = fmt_fields.index('CN')
                cn_str = smp_fields[cn_idx]
            except (ValueError, IndexError):
                continue

            try:
                cn = int(float(cn_str))
            except (ValueError, TypeError):
                continue

            value = copy_number_to_value(cn)
            if value is not None:
                records.append((gene_id, value))

    # Resolve official Hugo Symbols for all unique gene IDs
    unique_ids = list({r[0] for r in records})
    hugo_map = fetch_hugo_symbols(unique_ids)

    missing = [g for g in unique_ids if g not in hugo_map]
    if missing:
        print(
            f"Warning: no Hugo Symbol found for {len(missing)} gene ID(s), "
            f"using original ID as fallback: {', '.join(missing)}",
            file=sys.stderr,
        )

    rows = []
    for gene_id, value in records:
        hugo = hugo_map.get(gene_id, gene_id)
        rows.append(f"{hugo}\t{sample_id}\t{value}")

    out_path = os.path.join(os.getcwd(), 'data_cna.txt')
    write_header = not os.path.isfile(out_path) or os.path.getsize(out_path) == 0
    with open(out_path, 'a') as fh:
        if write_header:
            fh.write('Hugo_Symbol\tSample_Id\tValue\n')
        for row in rows:
            fh.write(row + '\n')


if __name__ == '__main__':
    main()
