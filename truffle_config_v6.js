module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // for more about customizing your Truffle configuration!
  contracts_directory: "./contracts/v6",
  networks: {
    development: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*" // Match any network id
    }
  },
  // Configure your compilers
  compilers: {
    solc: {
      version: "0.6.6"
    }
  },
  paths: {
    sources: "./contracts/v6",
  }
};
