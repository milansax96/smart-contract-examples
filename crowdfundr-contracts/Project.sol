//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "../node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract Project is ERC721 {
    uint256 public balance;
    uint256 public immutable goal;
    uint256 public immutable startDate;
    uint256 public tokenId;

    enum Status {Active, Success, Failure}
    Status projectStatus;

    mapping(address => uint) public contributions;
    address public immutable creator;

    event ContributionMade(address addr, uint amount);
    event Withdrawal(address addr, uint amount);
    event Refund(address addr, uint amount);
    event ProjectCancelled(address addr, address project);

    constructor (address _creator, string memory _name, string memory _symbol, uint256 _goal) ERC721(_name, _symbol) {
        goal = _goal;
        projectStatus = Status.Active;
        creator = _creator;
        startDate = block.timestamp;
    }

    receive() external payable {}

    function contribute() external payable {
        require(msg.value >= 0.01 ether, "must contribute at least 0.01 ETH");
        bytes memory _data = "";
        require(checkOnERC721Received(address(this), msg.sender, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
        require(projectStatus != Status.Success, "project goal met");
        require(!hasFailed() && projectStatus != Status.Failure, "project failed");
        balance += msg.value;
        contributions[msg.sender] += msg.value;
        if (balance >= goal) {
            projectStatus = Status.Success;
        }
        emit ContributionMade(msg.sender, msg.value);
    }

    function withdraw(uint amount) public {
        require(msg.sender == creator, "only creator");
        require(projectStatus == Status.Success, "project not successful");
        require(amount <= balance, "can't withdraw more than balance");
        balance -= amount;
        (bool success, ) = payable(creator).call{value: amount}("");
        require(success, "withdrawal unsuccessful");
        emit Withdrawal(creator, amount);
    }

    function refund() public {
        require(contributions[msg.sender] > 0, "non-contributor");
        require(hasFailed() && projectStatus == Status.Failure, "project hasn't failed");
        uint refundAmount = contributions[msg.sender];
        contributions[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "refund unsuccessful");
        emit Refund(msg.sender, refundAmount);
    }

    function cancel() public {
        require(msg.sender == creator, "only creator");
        require(!hasFailed() && projectStatus != Status.Failure, "project failed");
        require(projectStatus != Status.Success, "project goal met");
        projectStatus = Status.Failure;
        emit ProjectCancelled(creator, address(this));
    }

    function claimBadges() public {
        require(contributions[msg.sender] > 0, "non-contributor");
        uint256 nftBalance = contributions[msg.sender];
        while(contributions[msg.sender] >= 1 ether) {
            contributions[msg.sender] -= 1 ether;
        }
        while (nftBalance >= 1 ether) {
            _safeMint(msg.sender, tokenId++);
            nftBalance -= 1 ether;
        }
    }

    function transfer(address to, uint256 badgeId) public {
        safeTransferFrom(msg.sender, to, badgeId);
    }

    function hasFailed() private returns(bool) {
        if (block.timestamp - startDate >= 30 days) {
            if (projectStatus == Status.Active) {
                projectStatus = Status.Failure;
            }
            return true;
        }
        return false;
    }

    function checkOnERC721Received(address from, address to, uint256 id, bytes memory data) private returns (bool) {
        if (isContract(to)) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, id, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
        return true;
    }

    function isContract(address to) private view returns (bool) {
        return tx.origin != to;
    }

}
