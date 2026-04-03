## ArangoDB init (UUM-8D Broker)

This folder contains an `arangosh` init script that creates:

- Database: `uum8d_comms`
- Collections: `messages_pending`, `messages_delivered`, `messages_failed`
- Index: persistent on `messages_pending(to_node, priority, timestamp_ms)`

### Use with Docker (entrypoint init)

Mount the script into ArangoDB’s init directory (adjust to your image’s init behavior):

```yaml
services:
  arangodb:
    volumes:
      - ./services/uum8d_broker/arango/init_uum8d_comms.js:/docker-entrypoint-initdb.d/init_uum8d_comms.js:ro
```

### Use manually

```bash
arangosh --server.endpoint tcp://127.0.0.1:8529 --server.username root --server.password "<PASSWORD>" \
  --javascript.execute services/uum8d_broker/arango/init_uum8d_comms.js
```


