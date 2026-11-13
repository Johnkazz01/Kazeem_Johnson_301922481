// 03_bulk_and_index_demo.js
// Inserts 40,000 transaction_events documents with insertMany in batches of
// 1,000, then compares a COLLSCAN (hint({$natural:1})) against a compound
// index scan using explain("executionStats").
//
// Prints, for both BEFORE and AFTER:
//   Stage, Docs examined, Time ms.
//
// dropIndex is wrapped in try/catch so the script is re-runnable.

db = db.getSiblingDB("txnbank");

// Clean any prior bulk data so the script is re-runnable.
db.transaction_events.deleteMany({ transfer_reference: /^BULK-EVT-/ });

// Drop the compound index if it exists from a prior run.
try {
  db.transaction_events.dropIndex("idx_channel_amount_created");
  print("Dropped existing index idx_channel_amount_created.");
} catch (e) {
  print("No existing idx_channel_amount_created to drop (OK).");
}

// ----------------------------------------------------------------------
// Insert 40,000 documents in batches of 1,000.
// Channel rotates: branch / internet_banking / ussd.
// Amount is deterministic from the document index so the data is reproducible.
// ----------------------------------------------------------------------
const BATCH_SIZE = Int32(1000);
const TOTAL = Int32(40000);
const channels = ["branch", "internet_banking", "ussd"];
const start = new Date();

for (let batch = 0; batch < TOTAL / BATCH_SIZE; batch++) {
  const docs = [];
  for (let i = 0; i < BATCH_SIZE; i++) {
    const n = batch * 1000 + i;
    const channel = channels[n % 3];
    let metadata;
    if (channel === "branch") {
      metadata = {
        teller_id: "TLR-" + (n % 20),
        branch_code: "LMB-VI-01"
      };
    } else if (channel === "internet_banking") {
      metadata = {
        session_id: "SES-" + n,
        ip_address: "102.89.34." + (n % 250)
      };
    } else { // ussd
      metadata = {
        phone: "0802" + (10000000 + n).toString().slice(-8),
        ussd_code: "*737#"
      };
    }
    docs.push({
      _id: ObjectId(),
      event_id: "BULK-EVT-" + (100000 + n),
      transfer_reference: "TRF-BULK-" + (100000 + n),
      channel: channel,
      event_type: n % 12 === 0 ? "failed" : "settled",
      amount: Double(1000.0 + (n % 50) * 100),
      currency: "NGN",
      metadata: metadata,
      created_at: new Date(Date.now() - (n % 180) * 86400000)
    });
  }
  db.transaction_events.insertMany(docs, { ordered: false });
}

const insertMs = (new Date()) - start;
print("Inserted " + db.transaction_events.countDocuments({ event_id: /^BULK-EVT-/ })
      + " documents in " + insertMs + " ms.");

// ----------------------------------------------------------------------
// BEFORE: COLLSCAN using hint({$natural:1})
// Filter: channel == "internet_banking" AND amount >= 5800
// ----------------------------------------------------------------------
print("\n=== BEFORE: COLLSCAN ($natural hint) ===");
const before = db.transaction_events
  .find({ channel: "internet_banking", amount: { $gte: Double(5800.0) } })
  .hint({ $natural: 1 })
  .explain("executionStats");

// Helper: walk down the inputStage chain to find the leaf scan stage.
function leafStage(explainPlan) {
  const stats = explainPlan.executionStats || {};
  let s = stats.executionStages
       || (explainPlan.queryPlanner && explainPlan.queryPlanner.winningPlan)
       || {};
  while (s && s.inputStage) {
    s = s.inputStage;
  }
  return s.stage || "UNKNOWN";
}

const beforeStage  = leafStage(before);
const beforeDocs   = before.executionStats.totalDocsExamined;
const beforeTimeMs = before.executionStats.executionTimeMillis;
const beforeCount  = before.executionStats.nReturned;
print("Stage BEFORE:        " + beforeStage);
print("Docs BEFORE:         " + beforeDocs);
print("Time ms BEFORE:      " + beforeTimeMs);
print("Docs returned BEFORE: " + beforeCount);

// ----------------------------------------------------------------------
// AFTER: create a compound index on (channel, amount, created_at)
// ----------------------------------------------------------------------
db.transaction_events.createIndex(
  { channel: 1, amount: 1, created_at: 1 },
  { name: "idx_channel_amount_created" }
);
print("\nCreated compound index idx_channel_amount_created.");

print("\n=== AFTER: IXSCAN (compound index) ===");
const after = db.transaction_events
  .find({ channel: "internet_banking", amount: { $gte: Double(5800.0) } })
  .hint("idx_channel_amount_created")
  .explain("executionStats");

const afterStage  = leafStage(after);
const afterDocs   = after.executionStats.totalDocsExamined;
const afterTimeMs = after.executionStats.executionTimeMillis;
const afterCount  = after.executionStats.nReturned;
print("Stage AFTER:         " + afterStage);
print("Docs AFTER:          " + afterDocs);
print("Time ms AFTER:       " + afterTimeMs);
print("Docs returned AFTER: " + afterCount);

// ----------------------------------------------------------------------
// Summary table
// ----------------------------------------------------------------------
print("\n=== SUMMARY ===");
print("Stage     | Docs examined | Time ms");
print("BEFORE    | " + beforeDocs + " | " + beforeTimeMs);
print("AFTER     | " + afterDocs + " | " + afterTimeMs);

// Cleanup (optional - keep the documents for inspection, drop the index).
// To make the script fully re-runnable we drop the index at the top, not here.
print("\n03_bulk_and_index_demo.js complete.");
