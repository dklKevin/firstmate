---
name: droplock
description: >-
  Drop this home's fleet session lock so another Firstmate chat can start.
  Use when the captain invokes /droplock (e.g. "/droplock", "drop the fleet lock",
  "hand off the lock", "free the session lock for another chat").
user-invocable: true
metadata:
  internal: true
---

# droplock

Free this home's fleet session lock in one step so a new Firstmate chat can take the helm without a long handoff turn.

1. Run exactly:
   ```sh
   bin/fm-lock.sh release
   ```
2. Tell the captain in one short sentence that the lock is free (or already was), and that they can start the other chat.
3. Do not re-acquire the lock, spawn, steer, drain wakes, or start other work in this turn.
4. Do not explain the lock mechanism, Cursor archive behavior, or alternatives unless the captain asks.
