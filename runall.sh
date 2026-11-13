#!/usr/bin/env bash
# runall.sh - Johnson Kazeem, 2026/A/MIT/0691. Run from the repo folder: bash runall.sh   (or: bash runall.sh 3 to resume from P3)
set -uo pipefail
START="${1:-1}"
REPO="$(pwd)"
K="$HOME/kit/advanced-database-portfolio"
if [ ! -d "$K" ]; then
  mkdir -p "$HOME/kit"
  Z=$(ls "$REPO"/Johnson_Kazeem_FIXED.zip 2>/dev/null | head -1)
  [ -n "$Z" ] || { echo "!!! Johnson_Kazeem_FIXED.zip not found in $REPO - type ls and tell Joseph"; exit 1; }
  unzip -q -o "$Z" -d "$HOME/kit"
fi
sudo pg_ctlcluster 16 main start 2>/dev/null || sudo service postgresql start 2>/dev/null || true
pgrep -x mongod >/dev/null || sudo runuser -u mongodb -- mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log --bind_ip 127.0.0.1 --port 27017 --fork >/dev/null 2>&1 || true
if ! psql -d txnbank -c 'SELECT 1' >/dev/null 2>&1 || ! python3 -c 'import psycopg2' 2>/dev/null; then echo "--- running setup"; bash "$K/setup.sh" || { echo "!!! setup FAILED - send Joseph the output"; exit 1; }; fi
for N in 1 2 3 4 5; do
  [ "$N" -lt "$START" ] && continue
  case $N in 1) F=portfolio-1-database-design;; 2) F=portfolio-2-query-optimisation;; 3) F=portfolio-3-transactions-concurrency;; 4) F=portfolio-4-nosql;; 5) F=portfolio-5-distributed-cloud;; esac
  rm -rf "$REPO/$F"; cp -r "$K/$F" "$REPO/$F"
  echo "################ RUNNING P$N"
  if ! bash "$REPO/$F/run_p$N.sh" 2>&1 | tee "$REPO/$F/p${N}_output.log"; then :; fi
  if ! grep -q "P$N COMPLETE" "$REPO/$F/p${N}_output.log"; then echo "!!! P$N FAILED - send Joseph $F/p${N}_output.log"; exit 1; fi
  git add -A && git commit -q -m "Portfolio $N: run scripts and real output" && git push -q 2>/dev/null || true
done
cp "$K/collect_results.sh" "$REPO/collect_results.sh"
bash "$REPO/collect_results.sh"
git add -A && git commit -q -m "Collect results" && git push -q 2>/dev/null || true
command -v code >/dev/null 2>&1 && code my_results.txt || cat my_results.txt
