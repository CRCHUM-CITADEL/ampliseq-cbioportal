#!/usr/bin/env python3
"""
Parse a *-basespace-cnv.final.vcf file and write CNA data compatible with cBioPortal.
- Gene name: ID column
- Copy number: FORMAT CN field in sample column named Sample
- Only FILTER=PASS records are processed
- CN mapping: 0→-2, 1→-1, 2→0, 3→1, >=4→2
Usage: python3 format_cna_vcf.py <cnv.vcf[.gz]> <Sample_Id>
"""

import sys
import os
import gzip


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


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <cnv.vcf[.gz]> <Sample_Id>", file=sys.stderr)
        sys.exit(1)

    vcf_file, sample_id = sys.argv[1], sys.argv[2]

    opener = gzip.open if vcf_file.endswith('.gz') else open
    rows = []
    format_col = 8   # FORMAT is column 8 (0-based)
    sample_col = 9   # sample column is column 9 by default

    with opener(vcf_file, 'rt') as fh:
        for line in fh:
            if line.startswith('##'):
                continue
            if line.startswith('#CHROM'):
                # Locate the sample column named 'Sample'
                headers = line.lstrip('#').rstrip('\n').split('\t')
                try:
                    sample_col = next(
                        i for i, h in enumerate(headers)
                        if h.lower() == 'sample'
                    )
                except StopIteration:
                    # Fall back to standard column 9 if no Sample header found
                    sample_col = 9
                continue

            parts = line.rstrip('\n').split('\t')
            if len(parts) <= sample_col:
                continue

            vcf_filter = parts[6]
            if vcf_filter != 'PASS':
                continue

            gene = parts[2]
            if not gene or gene == '.':
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
                rows.append(f"{gene}\t{sample_id}\t{value}")

    out_path = os.path.join(os.getcwd(), 'data_cna.txt')
    write_header = not os.path.isfile(out_path) or os.path.getsize(out_path) == 0
    with open(out_path, 'a') as fh:
        if write_header:
            fh.write('Hugo_Symbol\tSample_Id\tValue\n')
        for row in rows:
            fh.write(row + '\n')


if __name__ == '__main__':
    main()
