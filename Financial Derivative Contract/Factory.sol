pragma solidity ^0.6.0;

import "https://github.com/120BPM/SDC/Swap.sol";
/*Lifepath*/
//load oracle
//load safemath
//import to Swap SDC
//Factory fct is frontend

contract Factory {
    address[] public newContracts;
    address public creator;
    address public oracleID; //address of Oracle
    uint public fee; //Cost of contract in Wei

    modifier onlyOwner{require(msg.sender == creator); _;}
    event Print(address _name, address _value);
    event FeeChange(uint _newValue);

    //Common pattern to use a hub/factory contract to create multiple instances of a standard contract.
    function Factory (address _oracleID, uint _fee) public{
        creator = msg.sender;  
        oracleID = _oracleID;
        fee = _fee;
    }

    function setFee(uint _fee) public onlyOwner{
      fee = _fee;
      FeeChange(fee);
    }

    //call fct. Pay fee, get returned swap address
    function createContract () public payable returns (address){
        require(msg.value == fee);
        address newContract = new Swap(oracleID,msg.sender,creator);
        newContracts.push(newContract);
        Print(msg.sender,newContract); //event marker to see when new SDC's are pushed.
        return newContract;
    } 
    function withdrawFee() public onlyOwner {
        creator.transfer(this.balance);
    }
}


//Factory Value SC's
// ETH/USD:0x4870a9da5999209e03a70f48ec4eca924d3f6fe2
// BTC/USD:0xa9f6eabcc9da75ac320946506b98ca6bf76ce459