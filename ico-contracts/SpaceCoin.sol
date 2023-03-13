//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// @title SpaceCoin
// @author Milan Saxena
contract SpaceCoin is ERC20 {

    // @notice the owner of the contract
    address immutable public owner;
    // @notice the treasury account for storing SpaceCoin
    address immutable public treasuryAccount;

    // @dev Boolean that represents whether the tax is enabled
    bool public taxEnabled;

    // @notice Constructs the contract and mints the total 500,000 supply
    constructor (address _owner, address treasuryAddress) ERC20('Space Coin', 'SPC') {
        owner = _owner;
        treasuryAccount = treasuryAddress;
        _mint(msg.sender, 150000 * 10 ** uint(decimals()));
        _mint(treasuryAccount, 350000 * 10 ** uint(decimals()));
    }

    // @notice Transfers the amount of tokens to a particular address
    function _transfer(address to, uint256 amount) public override returns (bool) {
        if (taxEnabled) {
            super._transfer(treasuryAccount, amount * 2 / 100);
            super._transfer(to, amount - (amount * 2 / 100));
        } else {
            super._transfer(to, amount);
        }
        return true;
    }

    // @notice Toggles the value of taxEnabled
    function toggleTaxEnabled() public {
        require(msg.sender == owner, "only owner");
        taxEnabled = !taxEnabled;
    }

}
