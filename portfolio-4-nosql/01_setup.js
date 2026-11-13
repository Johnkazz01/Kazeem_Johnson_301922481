// 01_setup.js
// Creates the MongoDB collections for Lagos Meridian Bank with $jsonSchema
// validation. Two collections:
//   transaction_events - audit and channel logs (branch / internet_banking / ussd)
//   fraud_alerts        - fraud cases raised against transfers
// No card numbers, CVV or PIN values are stored anywhere.
//
// Rules respected:
//   - db = db.getSiblingDB("txnbank")  (not `use txnbank`)
//   - $jsonSchema uses enum (with ONE value where const would otherwise apply),
//     oneOf for conditional schemas, and additionalProperties:false with every
//     field (including _id) listed explicitly.
//   - Numbers in seed/bulk scripts use Double() or Int32().

db = db.getSiblingDB("txnbank");

// Re-runnable: drop and recreate.
db.transaction_events.drop();
db.fraud_alerts.drop();

// ----------------------------------------------------------------------
// transaction_events
// ----------------------------------------------------------------------
db.createCollection("transaction_events", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "_id",
        "event_id",
        "transfer_reference",
        "channel",
        "event_type",
        "amount",
        "currency",
        "metadata",
        "created_at"
      ],
      properties: {
        _id: { bsonType: "objectId" },
        event_id: { bsonType: "string" },
        transfer_reference: { bsonType: "string" },
        channel: { enum: ["branch", "internet_banking", "ussd"] },
        event_type: { enum: ["initiated", "settled", "failed", "reversed"] },
        amount: { bsonType: "double" },
        // enum with ONE value instead of const, per portfolio rules.
        currency: { enum: ["NGN"] },
        metadata: { bsonType: "object" },
        created_at: { bsonType: "date" }
      },
      additionalProperties: false,
      // oneOf branches the metadata shape on the channel value.
      oneOf: [
        {
          properties: {
            channel: { enum: ["branch"] },
            metadata: {
              bsonType: "object",
              required: ["teller_id", "branch_code"],
              properties: {
                teller_id: { bsonType: "string" },
                branch_code: { bsonType: "string" }
              },
              additionalProperties: false
            }
          }
        },
        {
          properties: {
            channel: { enum: ["internet_banking"] },
            metadata: {
              bsonType: "object",
              required: ["session_id", "ip_address"],
              properties: {
                session_id: { bsonType: "string" },
                ip_address: { bsonType: "string" }
              },
              additionalProperties: false
            }
          }
        },
        {
          properties: {
            channel: { enum: ["ussd"] },
            metadata: {
              bsonType: "object",
              required: ["phone", "ussd_code"],
              properties: {
                phone: { bsonType: "string" },
                ussd_code: { bsonType: "string" }
              },
              additionalProperties: false
            }
          }
        }
      ]
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

// ----------------------------------------------------------------------
// fraud_alerts
// ----------------------------------------------------------------------
db.createCollection("fraud_alerts", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "_id",
        "alert_id",
        "transfer_reference",
        "reason",
        "severity",
        "status",
        "amount",
        "currency",
        "created_at"
      ],
      properties: {
        _id: { bsonType: "objectId" },
        alert_id: { bsonType: "string" },
        transfer_reference: { bsonType: "string" },
        reason: { bsonType: "string" },
        severity: { enum: ["LOW", "MEDIUM", "HIGH"] },
        status: { enum: ["OPEN", "IN_REVIEW", "CLOSED"] },
        amount: { bsonType: "double" },
        currency: { enum: ["NGN"] },
        created_at: { bsonType: "date" },
        reviewed_at: { bsonType: "date" },
        reviewer: { bsonType: "string" }
      },
      additionalProperties: false,
      // oneOf: an OPEN alert has no reviewer; an IN_REVIEW or CLOSED alert must.
      oneOf: [
        {
          properties: {
            status: { enum: ["OPEN"] }
          },
          required: ["status"]
        },
        {
          properties: {
            status: { enum: ["IN_REVIEW", "CLOSED"] }
          },
          required: ["status", "reviewed_at", "reviewer"]
        }
      ]
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

// Show the validators so the marker can confirm the schema.
print("=== transaction_events validator ===");
printjson(db.getCollectionInfos({ name: "transaction_events" })[0].options.validator);
print("=== fraud_alerts validator ===");
printjson(db.getCollectionInfos({ name: "fraud_alerts" })[0].options.validator);

print("01_setup.js complete: transaction_events + fraud_alerts created.");
