const { default: BigNumber } = require("bignumber.js");

App = {
  web3Provider: null,
  contracts: {},

  init: function() {
    return App.initWeb3();
  },

  initWeb3: function() {
    // Initialize web3 and set the provider to the testRPC.
    if (typeof web3 !== 'undefined') {
      App.web3Provider = web3.currentProvider;
      web3 = new Web3(web3.currentProvider);
    } else {
      // set the provider you want from Web3.providers
      App.web3Provider = new Web3.providers.HttpProvider('http://127.0.0.1:9545');
      web3 = new Web3(App.web3Provider);
    }

    web3.eth.defaultAccount = web3.eth.accounts[0];

    return App.initContract();
  },

  initContract: function() {
    $.getJSON('OmsToken.json', function(data) {
      // Get the necessary contract artifact file and instantiate it with truffle-contract.
      var OmsTokenArtifact = data;
      App.contracts.OmsToken = TruffleContract(OmsTokenArtifact);

      // Set the provider for our contract.
      App.contracts.OmsToken.setProvider(App.web3Provider);

      // Retrieve the total circulating supply.
      App.getTotalSupply();

      // Use our contract to retieve and mark the adopted pets.
      return App.getBalances();
    });

    return App.bindEvents();
  },

  bindEvents: function() {
    $(document).on('click', '#transferButton', App.handleTransfer);
    $(document).on('click', '#balanceButton', App.getBalanceForAccount);
    $(document).on('click', '#rebaseButton', App.rebase);
  },

  handleTransfer: function(event) {
    event.preventDefault();

    var amount = parseInt($('#OmsTransferAmount').val());
    var toAddress = $('#OmsTransferAddress').val();

    console.log('Transfer ' + amount + ' Oms to ' + toAddress);

    var omsTokenInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.OmsToken.deployed().then(function(instance) {
        omsTokenInstance = instance;

        return omsTokenInstance.transfer(toAddress, amount, {from: account, gas: 100000});
      }).then(function(result) {
        alert('Transfer Successful!');
        return App.getBalances();
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },

  getBalances: function() {
    console.log('Getting balances...');

    var omsTokenInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.OmsToken.deployed().then(function(instance) {
        omsTokenInstance = instance;

        return omsTokenInstance.balanceOf(account);
      }).then(function(result) {
        let balance = new BigNumber(result).toString();

        $('#OmsBalance').text(balance);
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },

  getTotalSupply: function() {
    console.log('Getting total supply...');

    var omsTokenInstance;
    App.contracts.OmsToken.deployed().then(function(instance) {
      omsTokenInstance = instance;

      return omsTokenInstance.totalSupply();
    }).then(function(result) {
      let bigTotalSupply = new BigNumber(result).toString();

      totalSupply = result.c[0];

      $('#OmsTotalSupply').text(bigTotalSupply);
    }).catch(function(err) {
      console.log(err.message);
    });
  },

  getBalanceForAccount: function(event) {
    event.preventDefault();

    var fromAddress = $('#OmsBalanceAddress').val();

    console.log('Retrieve balance from ' + fromAddress);

    var omsTokenInstance;

    App.contracts.OmsToken.deployed().then(function(instance) {
      omsTokenInstance = instance;

      return omsTokenInstance.balanceOf(fromAddress);
    }).then(function(result) {
      balance = new BigNumber(result).toString();
      $('#OmsBalanceAmount').text(balance);
    }).catch(function(err) {
      console.log(err.message);
    });
  },

  rebase: function(event) {
    event.preventDefault();

    var rebaseAmount = $('#OmsRebaseAmount').val();

    console.log('Rebasing with amount: ' + rebaseAmount);

    var omsTokenInstance;

    App.contracts.OmsToken.deployed().then(function(instance) {
      omsTokenInstance = instance;

      return omsTokenInstance.rebase(rebaseAmount);
    }).then(function(result) {
      newTotalSupply = result.c[0];
      console.log('new total supply is: ' + newTotalSupply);
    }).catch(function(err) {
      console.log(err.message);
    });
  }
};

$(function() {
  $(window).load(function() {
    App.init();
  });
});
