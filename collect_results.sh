#!/usr/bin/env bash
# collect_results.sh - Johnson Kazeem, 2026/A/MIT/0691. Gathers the real logs into my_results.txt.
cd "$(dirname "$0")"
{
echo "RESULTS for Johnson Kazeem (2026/A/MIT/0691) generated $(date)"
for N in 1 2 3 4 5; do
  D=$(ls -d portfolio-$N-* 2>/dev/null | head -1)
  echo; echo "################ PORTFOLIO $N ($D)"
  L="$D/p${N}_output.log"
  if [ -f "$L" ]; then
    case $N in
      1) grep -E "PASS|FAIL|ERROR|balance check|bulk summary|unbalanced|failed_transfers|COMPLETE" "$L" | cut -c1-200 ;;
      2) grep -E "Execution Time|Seq Scan|Index|Bitmap|Planning|COMPLETE|===" "$L" | cut -c1-200 ;;
      3) grep -E "COMPLETE|===" "$L"; echo "--- race demos"; cat "$D/race_demos_output.log" 2>/dev/null ;;
      4) grep -E "COMPLETE|Stage|Docs|Time ms|BEFORE|AFTER|===" "$L" | cut -c1-200 ;;
      5) grep -E "COMPLETE|===|Execution Time|partition|rows|replica|primary|in_recovery|read-only|code|Replica" "$L" | cut -c1-200 ;;
    esac
  else
    echo "(no $L)"
  fi
done
} > my_results.txt
echo "wrote my_results.txt"
