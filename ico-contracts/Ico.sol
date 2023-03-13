//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import "./SpaceCoin.sol";
// @title ICO Contract for Space Coin
// @author Milan Saxena
contract ICO {
    // @notice ratio for exchange (i.e. 5 SPC for 1 ETH)
    uint256 public immutable ratio;
    // @dev spaceCoin instance for transfer of tokens
    SpaceCoin public immutable spaceCoin;

    // @notice total balance of the phase including previous phases
    uint256 public phaseBalance;
    // @dev boolean that keeps track of whether buying/redeeming is paused
    bool public isPaused;

    // @dev Enum for representing different phases of ICO
    enum Phase {Seed, General, Open}
    // @notice Represents the specific phase that the ICO is currently in
    Phase public icoPhase;

    // @notice Stores the users who are allowed to invest in the Seed Phase
    mapping(address => bool) public allowList;
    // @notice Keeps track of all investments for each investor
    mapping(address => uint) public investments;

    /** @notice Initializes the contract with a SpaceCoin instance, treasury address,
        the ratio, and the Seed Phase Round */
    constructor (address _treasuryAccountAddress) {
        spaceCoin = new SpaceCoin(msg.sender, _treasuryAccountAddress);
        ratio = 5;
        icoPhase = Phase.Seed;
    }

    // @notice Allows a user to purchase Space Coin if not paused
    // @notice Allows a user to purchase Space Coin if they are in the allowList and the Phase is Seed
    /** @notice Allows a user to purchase if their individual contribution limit doesn't
        exceed 1500 ETH during Seed & 3000 ETH during General */
    /** @notice Allows a user to purchase if the total contribution
        doesn't exceed 15,000 ETH during seed and 30,000 thereafter for General and Open */
    function buySpaceCoin() public payable {
        require(!isPaused, "buying paused");
        require(_checkIcoPhaseConditions(msg.sender), "can't invest");
        require(_checkTotalContributionLimit(msg.value), "total contribution limit exceeded");
        require(_checkIndividualContributionLimit(msg.value), "individual contribution limit exceeded");
        phaseBalance += msg.value;
        investments[msg.sender] += msg.value;
    }

    // @notice Allows a user to redeem if not paused and Phase is Open
    function redeemSPCTokens() public {
        require(!isPaused, "redeeming paused");
        require(investments[msg.sender] > 0, "nothing to redeem");
        require(icoPhase == Phase.Open, "not open");
        uint tokenWithdrawalAmount = investments[msg.sender] * ratio;
        investments[msg.sender] = 0;
        spaceCoin._transfer(msg.sender, tokenWithdrawalAmount);
    }

    // @notice Allows owner to pause buying/redeeming operations
    function togglePause() public {
        require(msg.sender == spaceCoin.owner(), "only owner");
        isPaused = !isPaused;
    }

    // @notice Allows owner to a user to the allowList
    function addUserToAllowList(address _investor) public {
        require(msg.sender == spaceCoin.owner(), "only owner");
        allowList[_investor] = true;
    }

    // @notice Allows owner to advance to the next phase of funding
    function advancePhase() public {
        require(msg.sender == spaceCoin.owner(), "only owner");
        if (icoPhase == Phase.Seed) {
            icoPhase = Phase.General;
        } else if (icoPhase == Phase.General) {
            icoPhase = Phase.Open;
        }
    }

    /** @notice Checks to see if the amount is within the individual contribution limit
        for the specified phase */
    function _checkIndividualContributionLimit(uint _amount) private view returns (bool) {
        if (icoPhase == Phase.Seed) {
            return investments[msg.sender] + _amount <= 1500 ether;
        } else if (icoPhase == Phase.General) {
            return investments[msg.sender] + _amount <= 1000 ether;
        } else {
            return true;
        }
    }

    /** @notice Checks to see if the amount is within the total contribution limit
        for the specified phase */
    function _checkTotalContributionLimit(uint _amount) private view returns (bool) {
        if (icoPhase == Phase.Seed) {
            return phaseBalance + _amount <= 15000 ether;
        } else {
            return phaseBalance + _amount <= 30000 ether;
        }
    }
    // @notice Checks if investor is in the allowList during Seed, true otherwise
    function _checkIcoPhaseConditions(address _investor) private view returns (bool) {
        if (icoPhase == Phase.Seed && !allowList[_investor]) {
            return false;
        }
        return true;
    }

}
