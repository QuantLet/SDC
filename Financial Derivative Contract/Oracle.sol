pragma solidity ^0.6.0;

//import "oraclize-api/usingOraclize.sol";
//Oraclize update Provable 
import "github.com/oraclize/ethereum-api/provableAPI.sol";


//The Oracle contract provides the reference prices for SDC's. Base SPI Oracle altered by R2 from Oraclize. https://provable.xyz/
//checkcheck TinyOracleh https://github.com/axic/tinyoracle
//checkcheck Chainlink https://github.com/smartcontractkit/chainlink
//checkcheck Gnosis https://github.com/gnosis/pm-contracts

contract Oracle is usingProvable{
    /*Variables*/
    //Private queryId for Provable callback
    //checkcheck API2 to Provable off chain calculation
    bytes32 private queryID;
    string public API;
    string public API2;
    string public usedAPI;

    /*Structs*/
    struct QueryInfo {
        uint value;
        bool queried;
        uint date;
        uint calledTime;
        bool called;
    }  
    //Mapping of documents stored in the oracle
    mapping(uint => bytes32) public queryIds;
    mapping(bytes32 => QueryInfo ) public info;

    /*Events*/
    event DocumentStored(uint _key, uint _value);
    event newProvableQuery(string description);

    /*Functions*/
    /*
    *@dev Constructor, set two public api strings
    *checkcheck RasPi Ticker PY Code
    *e.g. "json(https://api.gdax.com/products/BTC-USD/ticker).price"
    *"json(https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT).price"
    *or "json(https://api.gdax.com/products/ETH-USD/ticker).price"
    *"json(https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDT).price"
    *Town Crier, Reality Keys, Gnosis, Augur, BlockOne IQ, Streamr, BTC Relay, TrueBit
    */
     constructor(string _api, string _api2) public{
        API = _api;
        API2 = _api2;
    }

    /*
    *@dev RetrieveData - Returns stored value by given key
    *@param _date Daily unix timestamp of key storing value (GMT 00:00:00)
    */
    function retrieveData(uint _date) public constant returns (uint) {
        QueryInfo storage currentQuery = info[queryIds[_date]];
        return currentQuery.value;
    }

    /*
    *@dev PushData - send Provable query for entered API
    */
    function pushData() public payable{
        uint _key = now - (now % 86400);
        uint _calledTime = now;
        QueryInfo storage currentQuery = info[queryIds[_key]];
        require(currentQuery.queried == false  && currentQuery.calledTime == 0 || 
            currentQuery.calledTime != 0 && _calledTime >= (currentQuery.calledTime + 3600) &&
            currentQuery.value == 0);
        if (provable_getPrice("URL") > address(this).balance) {
            emit newProvableQuery("Provable query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            emit newProvableQuery("Provable queries sent");
            if (currentQuery.called == false){
                queryID = provable_query("URL", API);
                usedAPI=API;
            } else if (currentQuery.called == true ){
                queryID = provable_query("URL", API2);
                usedAPI=API2;  
            }

            queryIds[_key] = queryID;
            currentQuery = info[queryIds[_key]];
            currentQuery.queried = true;
            currentQuery.date = _key;
            currentQuery.calledTime = _calledTime;
            currentQuery.called = !currentQuery.called;
        }
    }

    /*get test API*/
    function getusedAPI() public view returns(string){
        return usedAPI;
    }
    
    /*
    *@dev Used by Provable to return value of PushData API call
    *@param _oraclizeID unique oraclize identifier of call
    *@param _result Result of API call in string format
    */
    function __callback(bytes32 _oraclizeID, string _result) public {
        QueryInfo storage currentQuery = info[_oraclizeID];
        require(msg.sender == provable_cbAddress() && _oraclizeID == queryID);
        currentQuery.value = parseInt(_result,3);
        currentQuery.called = false; 
        if(currentQuery.value == 0){
            currentQuery.value = 1;
        }
        emit DocumentStored(currentQuery.date, currentQuery.value);
    }

    /*
    *@dev allow contract to be funded in order to pay for oraclize calls
    */
    function fund() public payable {
      
    }

    /*
    *@dev Determine if Oracle was queried
    *@param _date Daily unix timestamp of key storing value (GMT 00:00:00)
    *@return true or false based upon whether an API query has been 
    *initialized (or completed) for given date
    */
    function getQuery(uint _date) public view returns(bool){
        QueryInfo storage currentQuery = info[queryIds[_date]];
        return currentQuery.queried;
    }
}


//testtest
//checkcheck Kraken Price Ticker https://github.com/provable-things/ethereum-examples/blob/master/solidity/
/*
pragma solidity >= 0.5.0 < 0.6.0;

import "github.com/provable-things/ethereum-api/provableAPI.sol";

contract KrakenPriceTicker is usingProvable {

    string public priceETHXBT;

    event LogNewProvableQuery(string description);
    event LogNewKrakenPriceTicker(string price);

    constructor()
        public
    {
        provable_setProof(proofType_Android | proofStorage_IPFS);
        update(); // Update price on contract creation...
    }

    function __callback(
        bytes32 _myid,
        string memory _result,
        bytes memory _proof
    )
        public
    {
        require(msg.sender == provable_cbAddress());
        update(); // Recursively update the price stored in the contract...
        priceETHXBT = _result;
        emit LogNewKrakenPriceTicker(priceETHXBT);
    }

    function update()
        public
        payable
    {
        if (provable_getPrice("URL") > address(this).balance) {
            emit LogNewProvableQuery("Provable query was NOT sent, please add some ETH to cover for the query fee!");
        } else {
            emit LogNewProvableQuery("Provable query was sent, standing by for the answer...");
            provable_query(60, "URL", "json(https://api.kraken.com/0/public/Ticker?pair=ETHXBT).result.XETHXXBT.c.0");
        }
    }
}






