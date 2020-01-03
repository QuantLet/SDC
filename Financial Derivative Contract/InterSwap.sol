
//Auferstanden aus Ruinen und dem Intershop--swap zugewandt!

pragma solidity ^0.6.1;
//pragma solidity ^0.4.18;


//https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/ownership/Ownable.sol
import  'openzeppelin-solidity/contracts/ownership/Ownable.sol';
import  'openzeppelin-solidity/contracts/math/SafeMath.sol';


contract InterSwap is Ownable{
    using SafeMath for uint256;

    event Deposited(address indexed payee, uint256 amount, uint256 timestamp);
    event Withdrawn(address indexed payee, uint256 amount, uint256 timestamp);

    struct InterSwapTerms {
        uint total_escrow_amount; //Anderkonto-Treuhand-Escrow set at 0.2% of notional amount.
        uint swap_rate; //7 decimal points converted to integer (0.0239539 or 2.39539% x10000000 = 239539)
        uint termStartUnixTimestamp;
        uint termEndUnixTimestamp; //MM, DD, YYYY or # of months from start timestamp
        // address fixed_to_var_owner;
        // address var_to_fixed_owner;
    }

    struct ProposalOwner {
        uint notional_amount;  //amount used to calculate escrow
        uint owner_input_rate; //current interest rate of proposal owner (applicant)
        uint termEndUnixTimestamp; //MM, DD, YYYY or # of months from start timestamp. Maturity date of the terms. Checkcheck formula.
        string owner_input_rate_type; //fixed or variable. If fixed, then proposal owner is fixed_to_var_owner, vice versa.
    }

    struct CounterpartyEscrow {
        uint escrowDepositTimestamp;
        uint escrow_amount_deposited;
    }

    struct ProposalEscrow {
        uint escrowDepositTimestamp;
        uint escrow_amount_deposited; //expressed in wei/ether
    }


    // Solidity does not support floating points; encode interest rates as percentages scaled up by a factor of 10,000.
    // Interest rates can max. have 4 decimal places of precision.
    // 10,000,000 => 1% interest rate; 1,000,000 => 0.1% interest rate; 100,000 => 0.01% interest rate
    // To convert an encoded interest rate into its equivalent multiplier (to calculate total interest), divide notional amount by INTEREST_RATE_SCALING_FACTOR_PERCENT (10,000,000 => 0.01 interest multiplier)
    uint public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10 ** 7; //10,000,000
    uint public constant INTEREST_RATE_SCALING_FACTOR_MULTIPLIER = INTEREST_RATE_SCALING_FACTOR_PERCENT * 100; //1,000,000,000
    uint public num;

    string public fixedRate = 'fixed';
    string public variableRate = 'variable';
    address public proposalOwner; //proposal owner address
    address public counterparty; //counterparty--CRIX owner address

    //checkcheck https://solidity.readthedocs.io/en/v0.4.21/types.html#mappings
    mapping (address => InterSwapTerms) public contractAddressToContractTerms; //uses SC address to map contract terms
    mapping (address => ProposalOwner) public proposalAddressToProposalOwner; //uses proposer address to get proposer information
    mapping (address => ProposalEscrow) public proposalAddressToProposalEscrow;
    mapping (address => CounterpartyEscrow) public counterpartyAddressToCounterpartyAddressEscrow;
    mapping (address => uint256) public payeeAddressToPayAmount;


    modifier onlyProposalOwner() {
        // require(msg.sender == contractAddressToContractTerms[address(this)][var_to_fixed_owner],"Only SDC terms propasal owner can call this function.");
        require(msg.sender == proposalOwner, "Only SDC terms propasal owner can call this function.");
        _;
    }

    modifier onlyCounterparty() {
        // require(msg.sender == contractAddressToContractTerms[address(this)][fixed_to_var_owner],"Only SDC conterparty can call this function.");
        require(msg.sender == counterparty, "Only SDC terms conterparty can call this function.");
        _;
    }

    modifier hasMatured(){
        InterSwapTerms memory int_swap_terms = contractAddressToContractTerms[address(this)]; //address(this) is the address of this SDC
        num++; //need to spend gas in order to get now timestamp

        require (now > int_swap_terms.termEndUnixTimestamp, "SDC has not matured yet.");
        _;

    }

    //run fct to register as InterSwap contract proposal owner (be called by the proposer)
    function registerProposalOwner(uint _notional_amount, uint _owner_input_rate, uint matured_date, string _owner_input_rate_type, address _proposal_owner) public {
        require(proposalAddressToProposalOwner[proposalOwner].notional_amount == 0);
        require( _proposal_owner == msg.sender);

        ProposalOwner memory proposal_owner = ProposalOwner({notional_amount: _notional_amount, owner_input_rate: _owner_input_rate, termEndUnixTimestamp: matured_date, owner_input_rate_type: _owner_input_rate_type});

        // if (keccak256(_owner_input_rate_type) == keccak256(fixedRate)) {
        //     InterSwapTerms memory int_swap_terms = InterSwapTerms({fixed_to_var_owner: _proposal_owner});
        //     proposalOwner = _proposal_owner; //store the address of the proposal owner
        // } else {
        //     InterSwapTerms memory int_swap_terms = InterSwapTerms({var_to_fixed_owner: _proposal_owner});
        //     proposalOwner = _proposal_owner;
        // }

        proposalOwner = _proposal_owner;
        //map the proposal owner address to proposal owner struct
        proposalAddressToProposalOwner[_proposal_owner] = proposal_owner;

        //map the contract's address to the struct
        // contractAddressToContractTerms[address(this)] = int_swap_terms;

    }


    //consider to have the counterparty call this function
    function registerCounterparty(address _counterparty) public {
        require (proposalOwner != address(0), "Needs to register the proposal owner first");
        require(counterparty == address(0));
        require(_counterparty == msg.sender);
        // InterSwapTerms memory int_swap_terms = contractAddressToContractTerms[address(this)]; //address(this) is the address of this contract

        //check if the address is not set. address(0) == empty address
        //if empty, then this is the counterparty
        // if (int_swap_terms.fixed_to_var_owner == address(0)) {
        //     int_swap_terms.fixed_to_var_owner = _counterparty;
        //     counterparty = _counterparty; //store the address of the counterparty
        // } else {
        //     int_swap_terms.var_to_fixed_owner = _counterparty;
        //     counterparty = _counterparty;
        // }

        //map the counterparty address to counterpary struct
        // counterpartyAddressToCounterparty[_counterparty];

        counterparty = _counterparty;
    }

    //can only be called when escrow is deposited
    function calculateEscrowAmount (uint _escrowPercent) internal returns (uint) {
        //Escrow set at 0.2% of notional (2,000,000 is the converted _escrowPercent)
        // InterSwapTerms memory int_swap_terms = contractAddressToContractTerms[address(this)];
        ProposalOwner memory proposal_owner = proposalAddressToProposalOwner[proposalOwner];
        //ex. notional_amount = 100,000
        // escrow amount could have decimals (cents) need to look at in future
        uint escrow_amount = proposal_owner.notional_amount.mul(_escrowPercent).div(INTEREST_RATE_SCALING_FACTOR_MULTIPLIER);
        return escrow_amount;
    }

    //the escrow amount is already calculated on the frontend.
    function proposerDepositIntoEscrow (uint _escrowAmount, uint _escrowPercent) public payable onlyProposalOwner {
        require(msg.value == _escrowAmount); //msg.value(in wei or ether) has to be the same as the escrow amount
        require(_escrowAmount == calculateEscrowAmount(_escrowPercent)); //require the proposal owner to send the same amount of calculated escrow
        require(proposalAddressToProposalEscrow[proposalOwner].escrow_amount_deposited == 0);

        ProposalEscrow memory proposal_escrow = ProposalEscrow({escrowDepositTimestamp: now, escrow_amount_deposited: _escrowAmount});
        proposalAddressToProposalEscrow[proposalOwner] = proposal_escrow;

        emit Deposited(proposalOwner, _escrowAmount, now);
    }

    function counterpartyDepositIntoEscrow (uint _escrowAmount, uint _escrowPercent) public payable onlyCounterparty {
        require(msg.value == _escrowAmount);
        require(_escrowAmount == calculateEscrowAmount(_escrowPercent)); //require the proposal owner to send the same amount of calculated escrow
        require(counterpartyAddressToCounterpartyAddressEscrow[counterparty].escrow_amount_deposited == 0);

        CounterpartyEscrow memory counterparty_escrow = CounterpartyEscrow({escrowDepositTimestamp: block.timestamp, escrow_amount_deposited: _escrowAmount});
        counterpartyAddressToCounterpartyAddressEscrow[counterparty] = counterparty_escrow;

        emit Deposited(counterparty, _escrowAmount, block.timestamp);
    }

    function escrowDepositsOf(address payee) public view returns (uint256) {
        require(payee == proposalOwner || payee == counterparty);

        if(payee == proposalOwner){
            return proposalAddressToProposalEscrow[payee].escrow_amount_deposited;
        }
        if(payee == counterparty){
            return counterpartyAddressToCounterpartyAddressEscrow[payee].escrow_amount_deposited;
        }

    }

    //checkcheck _swap_rate = 2.88% based on forward rate of US LIBOR 1 month market expected in 23 months if 24 month contract (1st day of contract maturity month)
    function mintInterSwap (uint _swap_rate) onlyOwner public {
        // InterSwapTerms memory int_swap_terms = contractAddressToContractTerms[address(this)];
        ProposalOwner memory proposal_owner = proposalAddressToProposalOwner[proposalOwner]; //this gives us the proposal owner struct
        ProposalEscrow memory proposal_escrow = proposalAddressToProposalEscrow[proposalOwner]; //This gives us the proposal escrow struct
        CounterpartyEscrow memory counterparty_escrow = counterpartyAddressToCounterpartyAddressEscrow[counterparty];

        require (proposal_escrow.escrow_amount_deposited != 0); //making sure proposal owner has deposited the money
        require (counterparty_escrow.escrow_amount_deposited != 0);
        require (proposal_escrow.escrow_amount_deposited == counterparty_escrow.escrow_amount_deposited);
        require (_swap_rate > 0);
        require (proposalOwner != 0);
        require (counterparty != 0);

        uint totalEscrowAmount = proposal_escrow.escrow_amount_deposited.add(counterparty_escrow.escrow_amount_deposited);
        uint timeStampStart = now;

        InterSwapTerms memory interswap_terms = InterSwapTerms({total_escrow_amount: totalEscrowAmount, swap_rate: _swap_rate, termStartUnixTimestamp: timeStampStart, termEndUnixTimestamp: proposal_owner.termEndUnixTimestamp});

        contractAddressToContractTerms[address(this)] = interswap_terms;
    }

    // function getEndLibor(uint end_LIBOR) internal hasMatured onlyOwner returns (uint){
    //     //this function only called when contract is matured
    //     //contact oracle (or array for demo) to get one-month LIBOR at beginning of maturity month

    //     // uint end_LIBOR = msg.data;

    //     return end_LIBOR;
    // }

    //tst remove hasMatured modifier
    function VarToFixedPayoutCalc(uint _end_LIBOR) public onlyOwner returns (uint VarToFixedPayout){
        //2.9% = 0.029 LIBOR will be scaled to 29,000,000
        //0.88% = 0.0088 scaled to 8,800,000 LIBOR
        //_end_LIBOR to be passed into function = 29,000,000
        //swap rate will be scaled to 28,800,000 (2.88% = 0.0288)
        //cnotional amount = 100,000

        //if LIBOR increases (is positive) VarToFixed owner gets a profit
        //if LIBOR decreases (is negative) VarToFixed owner gets a loss
        //divide rates by 120,000,000 (with 7 zeroes) to convert from annual to monthly and from integer to 7 decimal places

        ProposalOwner memory proposal_owner = proposalAddressToProposalOwner[proposalOwner];
        InterSwapTerms memory int_swap_terms = contractAddressToContractTerms[address(this)]; //address(this) is address of this SDC

        uint VarToFixedGain;
        uint VarToFixedLoss;
        // uint end_LIBOR = getEndLibor();
        uint end_LIBOR = _end_LIBOR;
        uint _swap_rate = int_swap_terms.swap_rate;
        uint _notional_amount = proposal_owner.notional_amount;
        uint _escrow_amount;
        uint months = 12;
        uint MONTHLY_INTEREST_RATE_SCALING_FACTOR_MULTIPLIER = months.mul(INTEREST_RATE_SCALING_FACTOR_MULTIPLIER);

        address varToFixedOwner;

        if (keccak256(proposal_owner.owner_input_rate_type) == keccak256(variableRate)) {
            _escrow_amount = proposalAddressToProposalEscrow[proposalOwner].escrow_amount_deposited;
            varToFixedOwner = proposalOwner;
        } else {
            _escrow_amount = counterpartyAddressToCounterpartyAddressEscrow[counterparty].escrow_amount_deposited;
            varToFixedOwner = counterparty;
        }


        //when end_LIBOR gone up experience gain
        if (end_LIBOR > _swap_rate){
            VarToFixedGain = (_notional_amount.mul(end_LIBOR.sub(_swap_rate))).div(MONTHLY_INTEREST_RATE_SCALING_FACTOR_MULTIPLIER); //166.666
        }
        //when end_LIBOR gone down experience loss
        if (end_LIBOR <= _swap_rate){
            VarToFixedLoss = (_notional_amount.mul(_swap_rate.sub(end_LIBOR))).div(MONTHLY_INTEREST_RATE_SCALING_FACTOR_MULTIPLIER);
        }

        //VarToFixedGain is limited by _escrow_amount
        //if VarToFixedGain is greater than _escrow_amount
        //gain cannot exceed others escrow
        if (VarToFixedGain > _escrow_amount){
            VarToFixedGain = _escrow_amount;
        }
        //if VarToFixedLoss is greater than _escrow_amount
        //loss cannot excess own escrow
        if (VarToFixedLoss > _escrow_amount){
            VarToFixedLoss = _escrow_amount;
        }

        VarToFixedPayout = _escrow_amount + VarToFixedGain - VarToFixedLoss;

        payeeAddressToPayAmount[varToFixedOwner] = VarToFixedPayout;

        return VarToFixedPayout;
    }

    function FixedToVarPayoutCalc(uint _end_LIBOR) public onlyOwner returns(uint FixedToVarPayout){
        //if LIBOR increases (is positive) FixedToVar owner gets loss
        //if LIBOR decreases (is negative) FixedToVar owner gets profit
        ProposalOwner memory proposal_owner = proposalAddressToProposalOwner[proposalOwner];
        InterSwapTerms memory int_swap_terms = contractAddressToContractTerms[address(this)]; //address(this) is the address of this contract

        uint FixedToVarGain;
        uint FixedToVarLoss;
        // uint end_LIBOR = getEndLibor();
        uint end_LIBOR = _end_LIBOR;
        uint _swap_rate = int_swap_terms.swap_rate;
        uint _notional_amount = proposal_owner.notional_amount;
        uint _escrow_amount;
        uint months = 12;
        uint MONTHLY_INTEREST_RATE_SCALING_FACTOR_MULTIPLIER = months.mul(INTEREST_RATE_SCALING_FACTOR_MULTIPLIER);

        address fixedToVarOwner;


        if (keccak256(proposal_owner.owner_input_rate_type) == keccak256(fixedRate)) {
            _escrow_amount = proposalAddressToProposalEscrow[proposalOwner].escrow_amount_deposited;
            fixedToVarOwner = proposalOwner;
        } else {
            _escrow_amount = counterpartyAddressToCounterpartyAddressEscrow[counterparty].escrow_amount_deposited;
            fixedToVarOwner = counterparty;
        }

        if (end_LIBOR < _swap_rate){
            FixedToVarGain = (_notional_amount.mul(_swap_rate.sub(end_LIBOR))).div(MONTHLY_INTEREST_RATE_SCALING_FACTOR_MULTIPLIER);
        }
        if (end_LIBOR >= _swap_rate){
            FixedToVarLoss = (_notional_amount.mul(end_LIBOR.sub(_swap_rate))).div(MONTHLY_INTEREST_RATE_SCALING_FACTOR_MULTIPLIER);
        }
        if (FixedToVarGain > _escrow_amount){
            FixedToVarGain = _escrow_amount;  //checkcheck replace value of FixedToVarGain variable or new name?
        }
        if (FixedToVarLoss > _escrow_amount){
            FixedToVarLoss = _escrow_amount;  //checkcheck replace value of variable value or new name?
        }
        FixedToVarPayout = _escrow_amount + FixedToVarGain - FixedToVarLoss;

        payeeAddressToPayAmount[fixedToVarOwner] = FixedToVarPayout;

        return FixedToVarPayout;
    }

	//hasMatured modififer removed
    function proposalOwnerWithdrawPayment() public onlyProposalOwner {
        address payee = msg.sender;
        uint256 payment = payeeAddressToPayAmount[payee];

        require(payment != 0, "Nothing to withdraw");
        require(address(this).balance >= payment);

        //checkcheck reduce balance first to prevent re-entrancy attacks
        payeeAddressToPayAmount[payee] = 0;

        payee.transfer(payment);

        emit Withdrawn(payee, payment, block.timestamp);
    }

	//hasMatured modififer removed
    function counterpartyOwnerWithdrawPayment() public onlyCounterparty {
        address payee = msg.sender;
        uint256 payment = payeeAddressToPayAmount[payee];

        require(payment != 0,"There is nothing to withdraw");
        require(address(this).balance >= payment);

        // reduce the balance first to prevent re-entrancy attacks
        payeeAddressToPayAmount[payee] = 0;

        payee.transfer(payment);

        emit Withdrawn(payee, payment, block.timestamp);
    }
}