'use strict';
function operation(backend, ws) {
  if (backend && backend.operation) return backend.operation(ws);
  return {
    uid: ws && ws.user && ws.user.id,
    profile: ws && ws.profile && { ...ws.profile },
    identity: ws && ws.identity && { ...ws.identity },
    assert() {},
    wait: action => action(),
  };
}
module.exports = { operation };
