// AO Runtime for HyperBEAM JavaScript smart contracts
// DETERMINISTIC: All non-deterministic functions are stubbed
 
const _outbox = [];
globalThis.state = {};
globalThis.msg = {};
globalThis.env = {};
globalThis._getOutbox = () => JSON.stringify(_outbox);
globalThis._clearOutbox = () => { _outbox.length = 0; };
 
// Deterministic PRNG (xorshift128+) seeded from message
let _seed = [1, 2];
globalThis._setSeed = (s1, s2) => { _seed = [s1 >>> 0, s2 >>> 0]; };
const _xorshift = () => {
    let s1 = _seed[0], s2 = _seed[1];
    _seed[0] = s2;
    s1 ^= s1 << 23;
    s1 ^= s1 >>> 17;
    s1 ^= s2;
    s1 ^= s2 >>> 26;
    _seed[1] = s1;
    return ((_seed[0] + _seed[1]) >>> 0) / 4294967296;
};
 
// Override Math.random with deterministic PRNG
Math.random = _xorshift;
 
// Override Date to use block timestamp from env
const _OriginalDate = Date;
globalThis.Date = function(...args) {
    if (args.length === 0) {
        // new Date() uses block timestamp
        const ts = (env && env.Timestamp) || 0;
        return new _OriginalDate(ts);
    }
    return new _OriginalDate(...args);
};
globalThis.Date.now = () => (env && env.Timestamp) || 0;
globalThis.Date.parse = _OriginalDate.parse;
globalThis.Date.UTC = _OriginalDate.UTC;
 
globalThis.Handlers = {
    _h: {},
    add: (n, f) => { Handlers._h[n] = f; },
    remove: (n) => { delete Handlers._h[n]; },
    list: () => Object.keys(Handlers._h),
    handle: (m) => {
        const h = Handlers._h[m.Action || m.action] || Handlers._h['default'];
        return h ? h(m) : { error: 'No handler: ' + (m.Action || m.action) };
    }
};
 
globalThis.ao = {
    send: (m) => { if (m && m.Target) _outbox.push(JSON.parse(JSON.stringify(m))); },
    log: () => {}
};