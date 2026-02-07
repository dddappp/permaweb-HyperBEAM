// aojs/aojs-modules/counter.js
state.count = state.count || 0;
 
Handlers.add('Increment', () => {
    state.count += 1;
    return { count: state.count };
});
 
Handlers.add('Decrement', () => {
    state.count -= 1;
    return { count: state.count };
});
 
Handlers.add('GetCount', () => ({ count: state.count }));
 
Handlers.add('Reset', () => {
    state.count = 0;
    return { count: 0 };
});