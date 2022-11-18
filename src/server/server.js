import FlightSuretyApp from '../../build/contracts/FlightSuretyApp.json';
import Config from './config.json';
import Web3 from 'web3';
import express from 'express';


let config = Config['localhost'];
let web3 = new Web3(new Web3.providers.WebsocketProvider(config.url.replace('http', 'ws')));
web3.eth.defaultAccount = web3.eth.accounts[0];
let flightSuretyApp = new web3.eth.Contract(FlightSuretyApp.abi, config.appAddress);

const accountOffset = 20;

const oracles = [];

web3.eth.getAccounts().then((accounts) => {
    while (oracles.length < 20) {
        let address = accounts[accountOffset + oracles.length];
        oracles.push(address);
        try {
            console.log('@@@@@@register oracle', address);
            flightSuretyApp.methods.registerOracle().send({from: address, value: web3.utils.toWei('1', 'ether')});
        } catch (e) {
            console.log('@@@@@error registering oracle', e);
        }
    }
});

flightSuretyApp.events.OracleRequest({
    fromBlock: 0
  }, async function (error, event) {
    if (error) console.log(error)
    console.log(event);
    for (let oracle of oracles) {
        const indexes = await flightSuretyApp.methods.getMyIndexes().call({from: oracle});
        if (indexes.includes(event.returnValues.index)) {
            console.log('@@@@@oracle', oracle, 'is responding to index', event.returnValues.index);
            let statusCode = Math.floor(Math.random() * 6) * 10;
            console.log('@@@@@statusCode', statusCode);
            flightSuretyApp.methods.submitOracleResponse(event.returnValues.index, event.returnValues.airline, event.returnValues.flight, event.returnValues.timestamp, statusCode).send({from: oracle});
        }

    }
});

const app = express();
app.get('/api', (req, res) => {
    res.send({
      message: 'An API for use with your Dapp!'
    })
})

export default app;


