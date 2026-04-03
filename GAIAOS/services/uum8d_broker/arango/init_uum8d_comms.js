// ArangoDB init script for UUM-8D broker queue storage
// Usage (inside arangosh):
//   db._useDatabase('_system');
//   require('/docker-entrypoint-initdb.d/init_uum8d_comms.js');

(function () {
  const dbName = "uum8d_comms";

  db._useDatabase("_system");
  try {
    db._createDatabase(dbName);
  } catch (e) {
    // ok if exists
  }

  db._useDatabase(dbName);

  function ensureCollection(name) {
    try {
      db._create(name);
    } catch (e) {
      // ok if exists
    }
  }

  ensureCollection("messages_pending");
  ensureCollection("messages_delivered");
  ensureCollection("messages_failed");

  // Indexes: support broker poll ordering and operational queries.
  try {
    db.messages_pending.ensureIndex({
      type: "persistent",
      fields: ["to_node", "priority", "timestamp_ms"],
    });
  } catch (e) {}

  // TTL index for automatic expiry (based on timestamp_ms).
  // WARNING: Arango TTL index expects a date (seconds) field in many setups.
  // This script does not force TTL to avoid accidental mismatches; keep expiry policy external until confirmed.
  // If you want TTL, add a dedicated `created_at_s` field and TTL-index it.

  print("OK: initialized " + dbName + " collections + indexes (persistent)");
})();


