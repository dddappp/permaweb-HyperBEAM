// aojs/aojs-modules/token.js
state.balances = state.balances || {};
state.name = state.name || 'TestToken';
state.ticker = state.ticker || 'TST';
state.totalSupply = state.totalSupply || 0;
 
Handlers.add('Info', () => ({
    name: state.name,
    ticker: state.ticker,
    totalSupply: state.totalSupply
}));
 
Handlers.add('Balance', (msg) => {
    const target = (msg.Tags && msg.Tags.Target) || msg.From || 'unknown';
    return { balance: state.balances[target] || 0 };
});
 
Handlers.add('Mint', (msg) => {
    const qty = parseInt((msg.Tags && msg.Tags.Quantity) || '0');
    const recipient = msg.From || 'unknown';
    state.balances[recipient] = (state.balances[recipient] || 0) + qty;
    state.totalSupply += qty;
    return { success: true, balance: state.balances[recipient] };
});
 
Handlers.add('Transfer', (msg) => {
    const from = msg.From || 'unknown';
    const to = msg.Tags && msg.Tags.Recipient;
    const qty = parseInt((msg.Tags && msg.Tags.Quantity) || '0');
 
    if (!to || qty <= 0) {
        return { error: 'Invalid transfer' };
    }
 
    const fromBalance = state.balances[from] || 0;
    if (fromBalance < qty) {
        return { error: 'Insufficient balance' };
    }
 
    state.balances[from] = fromBalance - qty;
    state.balances[to] = (state.balances[to] || 0) + qty;
 
    // Send notification to recipient
    ao.send({
        Target: to,
        Action: 'Credit-Notice',
        Quantity: String(qty),
        Sender: from
    });
 
    return { success: true };
});