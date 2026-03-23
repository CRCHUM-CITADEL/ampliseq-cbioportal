#!/usr/bin/env python3.12
"""
Parse a *-basespace-cnv.final.vcf file and write CNA data compatible with cBioPortal.
- Gene name: Hugo Symbol fetched from mygene.info using CHROM:POS-END interval (hg19/human)
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


def chrom_with_prefix(chrom):
    """Ensure chromosome has chr prefix (e.g. '4' → 'chr4', 'chrX' → 'chrX')."""
    return chrom if chrom.startswith('chr') else 'chr' + chrom


def parse_end_from_info(info_str, pos):
    """Extract END= value from INFO field; fall back to pos+1 if absent."""
    for field in info_str.split(';'):
        if field.startswith('END='):
            try:
                return int(field[4:])
            except ValueError:
                pass
    return pos + 1


def fetch_hugo_by_interval(chrom, start, end):
    """Query mygene.info for genes overlapping chrN:start-end (hg19/human).

    Uses the genomic_pos_hg19 field to search by interval on the hg19 assembly.
    Returns a list of canonical Hugo Symbol strings; empty list on failure or no hit.
    """
    bare = chrom.replace('chr', '')
    q = f"genomic_pos_hg19.chr:{bare} AND genomic_pos_hg19.start:[{start} TO {end}]"
    params = urllib.parse.urlencode({
        "q": q,
        "fields": "symbol",
        "species": "human",
        "size": 50,
    })
    url = f"https://mygene.info/v3/query?{params}"
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            data = json.loads(resp.read())
        return [hit["symbol"] for hit in data.get("hits", []) if hit.get("symbol")]
    except Exception as e:
        print(f"Warning: mygene.info lookup failed for {chrom}:{start}-{end}: {e}", file=sys.stderr)
        return []


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <cnv.vcf[.gz]> <Sample_Id>", file=sys.stderr)
        sys.exit(1)

    vcf_file, sample_id = sys.argv[1], sys.argv[2]

    opener = gzip.open if vcf_file.endswith('.gz') else open
    records = []   # list of (chrom, start, end, cn_value)
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

            chrom = chrom_with_prefix(parts[0])
            try:
                pos = int(parts[1])
            except ValueError:
                continue
            end = parse_end_from_info(parts[7], pos)

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
                records.append((chrom, pos, end, value))

    # Resolve Hugo Symbols for all unique intervals
    unique_intervals = list({(r[0], r[1], r[2]) for r in records})
    interval_map: dict[tuple, list[str]] = {}
    for chrom, start, end in unique_intervals:
        symbols = fetch_hugo_by_interval(chrom, start, end)
        if not symbols:
            print(
                f"Warning: no Hugo Symbol found for {chrom}:{start}-{end}, "
                f"using interval as fallback",
                file=sys.stderr,
            )
            symbols = [f"{chrom}:{start}-{end}"]
        interval_map[(chrom, start, end)] = symbols

    rows = []
    for chrom, start, end, value in records:
        for hugo in interval_map[(chrom, start, end)]:
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
