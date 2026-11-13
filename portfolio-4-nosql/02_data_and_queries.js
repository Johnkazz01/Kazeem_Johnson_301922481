// 02_data_and_queries.js
// Seeds a small set of transaction_events and fraud_alerts documents for Lagos
// Meridian Bank, then runs 3 aggregation pipelines.
// Numbers use Double() and Int32() per the portfolio rules.
// No card numbers, CVV or PIN values are stored.

db = db.getSiblingDB("txnbank");

// Clean prior seed data so the script is re-runnable.
db.transaction_events.deleteMany({});
db.fraud_alerts.deleteMany({});

// ----------------------------------------------------------------------
// Seed: 12 transaction events across the 3 channels
// ----------------------------------------------------------------------
db.transaction_events.insertMany([
  {
    _id: ObjectId(),
    event_id: "EVT-001",
    transfer_reference: "TRF-0000001",
    channel: "branch",
    event_type: "settled",
    amount: Double(15000.00),
    currency: "NGN",
    metadata: { teller_id: "TLR-VI-01", branch_code: "LMB-VI-01" },
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    event_id: "EVT-002",
    transfer_reference: "TRF-0000002",
    channel: "internet_banking",
    event_type: "settled",
    amount: Double(27500.00),
    currency: "NGN",
    metadata: { session_id: "SES-7782", ip_address: "102.89.34.10" },
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    event_id: "EVT-003",
    transfer_reference: "TRF-0000003",
    channel: "ussd",
    event_type: "failed",
    amount: Double(3200.00),
    currency: "NGN",
    metadata: { phone: "08021234567", ussd_code: "*737#" },
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    event_id: "EVT-004",
    transfer_reference: "TRF-0000004",
    channel: "internet_banking",
    event_type: "settled",
    amount: Double(85000.00),
    currency: "NGN",
    metadata: { session_id: "SES-7783", ip_address: "102.89.34.11" },
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    event_id: "EVT-005",
    transfer_reference: "TRF-0000005",
    channel: "branch",
    event_type: "initiated",
    amount: Double(4500.00),
    currency: "NGN",
    metadata: { teller_id: "TLR-YB-02", branch_code: "LMB-YB-02" },
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    event_id: "EVT-006",
    transfer_reference: "TRF-0000006",
    channel: "ussd",
    event_type: "settled",
    amount: Double(12000.00),
    currency: "NGN",
    metadata: { phone: "08021234568", ussd_code: "*737#" },
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    event_id: "EVT-007",
    transfer_reference: "TRF-0000007",
    channel: "internet_banking",
    event_type: "failed",
    amount: Double(54000.00),
    currency: "NGN",
    metadata: { session_id: "SES-7784", ip_address: "105.112.10.22" },
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    event_id: "EVT-008",
    transfer_reference: "TRF-0000008",
    channel: "branch",
    event_type: "settled",
    amount: Double(31000.00),
    currency: "NGN",
    metadata: { teller_id: "TLR-AB-03", branch_code: "LMB-AB-03" },
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    event_id: "EVT-009",
    transfer_reference: "TRF-0000009",
    channel: "ussd",
    event_type: "reversed",
    amount: Double(2000.00),
    currency: "NGN",
    metadata: { phone: "08021234569", ussd_code: "*737#" },
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    event_id: "EVT-010",
    transfer_reference: "TRF-0000010",
    channel: "internet_banking",
    event_type: "settled",
    amount: Double(67500.00),
    currency: "NGN",
    metadata: { session_id: "SES-7785", ip_address: "102.89.34.12" },
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    event_id: "EVT-011",
    transfer_reference: "TRF-0000011",
    channel: "branch",
    event_type: "settled",
    amount: Double(9500.00),
    currency: "NGN",
    metadata: { teller_id: "TLR-PH-04", branch_code: "LMB-PH-04" },
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    event_id: "EVT-012",
    transfer_reference: "TRF-0000012",
    channel: "internet_banking",
    event_type: "settled",
    amount: Double(42500.00),
    currency: "NGN",
    metadata: { session_id: "SES-7786", ip_address: "105.112.10.23" },
    created_at: new Date()
  }
]);

// ----------------------------------------------------------------------
// Seed: 3 fraud alerts
// ----------------------------------------------------------------------
db.fraud_alerts.insertMany([
  {
    _id: ObjectId(),
    alert_id: "FRD-001",
    transfer_reference: "TRF-0000007",
    reason: "Velocity check: 6 transfers from same IP in 2 minutes",
    severity: "HIGH",
    status: "IN_REVIEW",
    amount: Double(54000.00),
    currency: "NGN",
    created_at: new Date(),
    reviewed_at: new Date(),
    reviewer: "ops.officer@lagosmeridianbank.ng"
  },
  {
    _id: ObjectId(),
    alert_id: "FRD-002",
    transfer_reference: "TRF-0000003",
    reason: "USSD transfer to dormant account",
    severity: "LOW",
    status: "OPEN",
    amount: Double(3200.00),
    currency: "NGN",
    created_at: new Date()
  },
  {
    _id: ObjectId(),
    alert_id: "FRD-003",
    transfer_reference: "TRF-0000009",
    reason: "Reversed transfer from sanctioned-bank list",
    severity: "MEDIUM",
    status: "CLOSED",
    amount: Double(2000.00),
    currency: "NGN",
    created_at: new Date(),
    reviewed_at: new Date(),
    reviewer: "compliance.lead@lagosmeridianbank.ng"
  }
]);

print("Seed complete: " + db.transaction_events.countDocuments() + " events, "
      + db.fraud_alerts.countDocuments() + " fraud alerts.");

// ----------------------------------------------------------------------
// Pipeline 1: total transaction value and count by channel
// ----------------------------------------------------------------------
print("\n=== Pipeline 1: total transaction value and count by channel ===");
const pipeline1 = [
  { $group: {
      _id: "$channel",
      total_value: { $sum: "$amount" },
      event_count: { $sum: Int32(1) }
  }},
  { $sort: { total_value: -1 } }
];
printjson(db.transaction_events.aggregate(pipeline1).toArray());

// ----------------------------------------------------------------------
// Pipeline 2: top 5 transfer references by event count (initiated + settled)
// ----------------------------------------------------------------------
print("\n=== Pipeline 2: top 5 transfer references by event count ===");
const pipeline2 = [
  { $match: { event_type: { $in: ["initiated", "settled"] } } },
  { $group: {
      _id: "$transfer_reference",
      events: { $sum: Int32(1) },
      total_amount: { $sum: "$amount" }
  }},
  { $sort: { events: -1, total_amount: -1 } },
  { $limit: Int32(5) }
];
printjson(db.transaction_events.aggregate(pipeline2).toArray());

// ----------------------------------------------------------------------
// Pipeline 3: failed event rate by channel
// ----------------------------------------------------------------------
print("\n=== Pipeline 3: failed event rate by channel ===");
const pipeline3 = [
  { $group: {
      _id: "$channel",
      total: { $sum: Int32(1) },
      failed: { $sum: { $cond: [{ $eq: ["$event_type", "failed"] }, Int32(1), Int32(0)] } }
  }},
  { $project: {
      channel: "$_id",
      total: 1,
      failed: 1,
      failed_rate_pct: { $multiply: [{ $divide: ["$failed", "$total"] }, Double(100.0)] }
  }},
  { $sort: { failed_rate_pct: -1 } }
];
printjson(db.transaction_events.aggregate(pipeline3).toArray());

print("\n02_data_and_queries.js complete.");
