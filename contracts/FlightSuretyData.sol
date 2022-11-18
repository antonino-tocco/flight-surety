pragma solidity ^0.8.17;

import "../node_modules/@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    // Flight status codes
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    uint256 private constant MINIMUM_AIRLINE_FUNDING = 10 ether;
    uint256 private constant MAXIMUM_INSURANCE_AMOUNT = 1 ether;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;
    mapping(address => uint8) private authorizedAppContracts;// Blocks all state changes throughout the contract if false

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
    }
    mapping(bytes32 => Flight) private flights;

    struct Airline {
        string name;
        address airlineAddress;
        bool isFunded;
    }

    struct PendingAirline {
        string name;
        address airlineAddress;
        address[] votesAirlines;
        uint256 votes;
    }

    mapping(address => Airline) private registeredAirlines;
    mapping(address => PendingAirline) private pendingAirlines;
    uint256 registeredAirlinesCount = 0;
    uint256 pendingAirlinesCount = 0;

    struct Passenger {
        address passengerAddress;
        mapping(bytes32 => uint256) insuredFlights;//mapping for insured flights
        uint256 credit;//amount of passenger credit saved
    }

    mapping(address => Passenger) private passengers;
    address[] passengerAddresses;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/


    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor() public
    {
        contractOwner = msg.sender;
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational()
    {
        require(operational, "Contract is currently not operational");
        _;
        // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireIsCallerAuthorized()
    {
        require(authorizedAppContracts[msg.sender] == 1, "Caller is not authorized");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */
    function isOperational() public view returns (bool)
    {
        return operational;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */
    function setOperatingStatus(bool mode) external requireContractOwner
    {
        operational = mode;
    }

    /**
    * @dev Sets authorized contract
    *
    */
    function authorizeAppContract(address appContractAddress) external
    {
        authorizedAppContracts[appContractAddress] = 1;
    }

    /**
    * @dev Unset authorized contract
    *
    */
    function deauthorizeAppContract(address appContractAddress) external
    {
        delete authorizedAppContracts[appContractAddress];
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function registerAirline(string memory name,address airlineAddress) external requireIsCallerAuthorized
    {
        registeredAirlines[airlineAddress] = (Airline({
            name: name,
            airlineAddress: airlineAddress,
            isFunded: false
        }));
        registeredAirlinesCount.add(1);
    }

    function addPendingAirline(string memory name, address airlineAddress, address voteAddress) external requireIsCallerAuthorized
    {
        pendingAirlines[airlineAddress] = PendingAirline({
            name: name,
            airlineAddress: airlineAddress,
            votesAirlines: new address[](0), //initialize empty storage array
            votes: 0
        });
        pendingAirlines[airlineAddress].votesAirlines.push(voteAddress);
        pendingAirlines[airlineAddress].votes.add(1);
    }

    function voteForAirline(address airlineAddress, address voteAddress) external
    {
        pendingAirlines[airlineAddress].votesAirlines.push(voteAddress);
        pendingAirlines[airlineAddress].votes++;
        if (pendingAirlines[airlineAddress].votes >= registeredAirlinesCount / 2) {
            registeredAirlines[airlineAddress] = Airline({
                name: pendingAirlines[airlineAddress].name,
                airlineAddress: airlineAddress,
                isFunded: false
            });
            registeredAirlinesCount.add(1);
            delete pendingAirlines[airlineAddress];
        }
    }

    function isAirlineRegistered(address airlineAddress) external returns (bool) {
        return registeredAirlines[airlineAddress].airlineAddress != address(0);
    }

    function isAirlinePending(address airlineAddress) external returns (bool) {
        return pendingAirlines[airlineAddress].airlineAddress != address(0);
    }

    function isAirlineFunded(address airlineAddress) external returns (bool){
        return registeredAirlines[airlineAddress].isFunded;
    }

    function getRegisteredAirlineCount() external returns (uint256){
        return registeredAirlinesCount;
    }

    function getVotesForAirline(address airlineAddress) external returns (uint256){
        return pendingAirlines[airlineAddress].votes;
    }

    function registerFlight(bytes32 key, address airline, uint256 timestamp) external
    {
        flights[key] = Flight({
            isRegistered: true,
            statusCode: STATUS_CODE_UNKNOWN,
            updatedTimestamp: timestamp,
            airline: airline
        });
    }

    function updateFlightStatus(bytes32 key, uint8 statusCode) external
    {
        flights[key].statusCode = statusCode;
    }


    /**
     * @dev Buy insurance for a flight
    *
    */
    function buy(bytes32 flightKey, address passengerAddress, uint256 insuredAmount  ) external payable
    {
        require(msg.value <= MAXIMUM_INSURANCE_AMOUNT, "Insurance cannot be more than 1 ether");
        require(msg.value > 0, "Insurance cannot be 0 ether");
        require(flights[flightKey].isRegistered, "Flight is not registered");
        require(flights[flightKey].statusCode == STATUS_CODE_UNKNOWN, "Flight has already landed");

        //add insurance
        if (passengers[passengerAddress].passengerAddress != address(0)) {
            require(passengers[passengerAddress].insuredFlights[flightKey] == 0, "Passenger already insured for this flight");
        } else {

            passengers[passengerAddress].passengerAddress = passengerAddress;
            passengers[passengerAddress].credit = 0;
        }
        passengers[passengerAddress].insuredFlights[flightKey] = msg.value;
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees(bytes32 flightKey) external
    {
        require(flights[flightKey].isRegistered, "Flight is not registered");
        require(flights[flightKey].statusCode == STATUS_CODE_LATE_AIRLINE, "Flight is not late");

        for (uint256 i = 0; i < passengerAddresses.length; i++) {
            if (passengers[passengerAddresses[i]].insuredFlights[flightKey] > 0) {
                passengers[passengerAddresses[i]].credit += passengers[passengerAddresses[i]].insuredFlights[flightKey] * 3 / 2;
            }
        }
    }


    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay(address insuredPassenger) external
    {
        require(insuredPassenger == tx.origin, "Contract cannot pay to a contract");
        require(passengers[insuredPassenger].passengerAddress != address(0), "Passenger is not insured");
        require(passengers[insuredPassenger].credit > 0, "Passenger has no credit");
        uint256 credit = passengers[insuredPassenger].credit;
        require(address(this).balance >= credit, "Contract has not enough credit");

        //the order of this two lines ensure that no re-entrancy attack works
        passengers[insuredPassenger].credit = 0;
        payable(insuredPassenger).transfer(credit);

    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */
    function fund() public payable
    {
        require(msg.value == MINIMUM_AIRLINE_FUNDING, "Funding amount must be 10 ether");
        require(registeredAirlines[msg.sender].airlineAddress != address(0), "Airline is not registered");

        registeredAirlines[msg.sender].isFunded = true;
    }

    function getFlightKey(address airline, string memory flight, uint256 timestamp) pure internal returns(bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    fallback() external payable
    {
        fund();
    }


}