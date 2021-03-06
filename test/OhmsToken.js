const OmsToken = artifacts.require("Oms");

contract('OmsToken', (accounts) => {
    it('should start with a total supply of 50,000,000,000,000,000', async () => {
        let omsTokenInstance = await OmsToken.deployed();
        let totalSupply = await omsTokenInstance.totalSupply();

        assert.equal(totalSupply.toString(), 50000000000000000, "50,000,000,000,000,000 isn't the total supply");
    }),
    it('should put 50,000,000,000,000,000 OmsToken in the first account', async () => {
        let omsTokenInstance = await OmsToken.deployed();
        let balance = await omsTokenInstance.balanceOf(accounts[0]);

        assert.equal(balance.toString(), 50000000000000000, "50,000,000,000,000,000 wasn't in the first account");
    });
});