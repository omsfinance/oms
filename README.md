# OMS

In-depth documentation on Oms and how it integrates with the rest of the Oms Platform is available at [Oms.Finance](https://oms.finance/)

# Local Development

## Install dependencies 

`npm install`

## Compile contracts

`truffle compile`

## Run tests

`truffle test`

## Flatten file


`truffle-flattener contracts/v4/Oms.sol > scratch/Oms.sol`
`truffle-flattener contracts/v4/OmsPolicy.sol > scratch/OmsPolicy.sol`
`truffle-flattener contracts/v4/Orchestrator.sol > scratch/Orchestrator.sol`
`truffle-flattener contracts/v6/Oracle.sol > scratch/Oracle.sol`

Use the following if you want to flatten the contract and also process only one SPDX licence identifier.

`truffle-flattener contracts/v4/Oms.sol | awk '/SPDX-License-Identifier/&&c++>0 {next} 1' > scratch/Oms.sol`
`truffle-flattener contracts/v4/OmsPolicy.sol | awk '/SPDX-License-Identifier/&&c++>0 {next} 1' > scratch/OmsPolicy.sol`
`truffle-flattener contracts/v4/Orchestrator.sol | awk '/SPDX-License-Identifier/&&c++>0 {next} 1' > scratch/Orchestrator.sol`
`truffle-flattener contracts/v6/Oracle.sol | awk '/SPDX-License-Identifier/&&c++>0 {next} 1' > scratch/Oracle.sol`

## Start Eth95 to run a local client to be able to interact with the Ethereum blockchain

`npm run run95`

Open Eth95 in a browser by going to `http://localhost:3000/`
