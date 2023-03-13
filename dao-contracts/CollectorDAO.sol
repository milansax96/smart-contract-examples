// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface INftMarketplace {
    /// @notice Returns the price of the NFT at the `nftContract`
    /// address with the given token ID `nftID`
    /// @param nftContract The address of the NFT contract to purchase
    /// @param nftId The token ID on the nftContract to purchase
    /// @return price ETH price of the NFT in units of wei
    function getPrice(address nftContract, uint256 nftId) external returns (uint256 price);

    /// @notice Purchase the specific token ID of the given NFT from the marketplace
    /// @param nftContract The address of the NFT contract to purchase
    /// @param nftId The token ID on the nftContract to purchase
    /// @return success true if the NFT was successfully transferred to the msg.sender, false otherwise
    function buy(address nftContract, uint256 nftId) external payable returns (bool success);
}

contract CollectorDAO {
    /// @notice name of the contract
    string public constant name = "Collector DAO";
    /// @notice ballot hash for signature voting
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool voteInFavor)");
    /// @notice domain hash for EIP 712 signature voting
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @dev storage variable that keeps track of the number of members
    uint256 public memberCount;

    /// @notice tracks state of each proposal
    enum ProposalState {Active, Failed, Passed, Executed}

    /// @notice core of each proposal with relevant parameters
    struct ProposalCore {
        uint256 startDate;
        uint256 deadline;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 blockNumber;
        uint256 totalEligibleVoters;
        ProposalState state;
        address creator;
        mapping(address => bool) voters;
    }

    /// @dev member struct which tracks votingPower & blockJoined
    struct Member {
        uint256 votingPower;
        uint256 blockJoined;
    }

    /// @notice maps user's address to a member struct
    mapping(address => Member) public memberships;
    /// @dev maps a proposal id to a ProposalCore struct
    mapping(uint256 => ProposalCore) public proposals;

    /// @dev Emits an event for each proposal created
    event ProposalCreated(address creator, string description);
    /// @dev Emits an event for each vote cast
    event VoteCast(address voter, uint256 proposalId, bool voteInFavor);
    /// @dev Emits an event for each executed proposal
    event ProposalExecuted(uint256 proposalId, address executor);

    /// @notice restricts users who are non-members from calling functions
    modifier onlyMember {
        // doing this to check if someone is actually a member
        require(memberships[msg.sender].votingPower > 0, "only members");
        _;
    }

    /// @notice allows a user to become a member for 1 ETH
    function becomeMember() payable external {
        require(msg.value == 1 ether, "need to deposit 1 ETH");
        require(memberships[msg.sender].votingPower == 0, "already member");
        memberships[msg.sender].votingPower += 1;
        memberships[msg.sender].blockJoined = block.number;
        memberCount++;
    }

    /// @notice allows a proposal to be hashed for access
    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 description
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, description)));
    }

    /// @notice allows a member to create a governance proposal
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external onlyMember returns (uint256) {
        require(targets.length == values.length && targets.length == calldatas.length && targets.length > 0, "invalid length");
        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        require(proposals[proposalId].creator == address(0), "proposal already exists");
        ProposalCore storage proposal = proposals[proposalId];

        proposal.startDate = block.timestamp;
        proposal.deadline = proposal.startDate + 7 days;

        proposal.blockNumber = block.number;
        proposal.state = ProposalState.Active;
        proposal.creator = msg.sender;

        proposal.totalEligibleVoters = memberCount;

        emit ProposalCreated(msg.sender, description);

        return proposalId;
    }

    /// @notice allows a user to cast a vote
    function castVote(uint256 proposalId, bool voteInFavor) external {
        _castVote(msg.sender, proposalId, voteInFavor);
    }


    /// @notice Allows a user to cast a vote by EIP 712 Signature
    function castVoteBySignatures(uint256[] memory proposalIds, bool[] memory votesInFavor, uint8[] memory v, bytes32[] memory r, bytes32[] memory s) external {
        require(proposalIds.length == votesInFavor.length && proposalIds.length == v.length && proposalIds.length == r.length && proposalIds.length == s.length && proposalIds.length > 0, "invalid length");
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), _getChainId(), address(this)));
        for (uint i = 0; i < proposalIds.length; i++) {
            bytes32 ballotHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalIds[i], votesInFavor[i]));
            bytes32 sigDigest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, ballotHash));
            address voter = ecrecover(sigDigest, v[i], r[i], s[i]);
            _castVote(voter, proposalIds[i], votesInFavor[i]);
        }
    }

    /// @notice executes a proposal with several arbitrary functions
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description) external {

        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        ProposalCore storage proposal = proposals[proposalId];
        require(getProposalStatus(proposalId) == ProposalState.Passed, "proposal hasn't passed");
        require(_quorumReached(proposalId), "quorum has not been reached");
        require(targets.length == values.length && targets.length == calldatas.length && targets.length > 0, "invalid length");

        proposal.state = ProposalState.Executed;
        memberships[proposal.creator].votingPower += 1;

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success,) = targets[i].call{value : values[i]}(calldatas[i]);
            require(success, "function call failed");
        }

        emit ProposalExecuted(proposalId, msg.sender);

        if (address(this).balance > 5 ether) {
            (bool success,) = payable(msg.sender).call{value : 0.01 ether}("");
            require(success, "transfer failed");
        }

    }

    /// @dev private function that handles vote casting logic
    function _castVote(address voter, uint256 proposalId, bool voteInFavor) onlyMember private {
        ProposalCore storage proposal = proposals[proposalId];
        require(block.timestamp <= proposal.deadline, "deadline has passed");
        require(!proposal.voters[voter], "already voted");
        require(memberships[voter].blockJoined <= proposal.blockNumber - 1, "must have joined at least in previous block");
        if (voteInFavor) {
            proposal.votesFor += memberships[voter].votingPower;
        } else {
            proposal.votesAgainst += memberships[voter].votingPower;
        }
        proposal.voters[voter] = true;

        emit VoteCast(voter, proposalId, voteInFavor);
    }

    /// @notice gets proposal status
    function getProposalStatus(uint256 proposalId) public returns (ProposalState) {
        ProposalCore storage proposal = proposals[proposalId];
        if (proposal.state == ProposalState.Executed) {
            return ProposalState.Executed;
        }
        return _updateProposalStatus(proposalId);
    }

    /// @notice updates a proposal's status
    function _updateProposalStatus(uint256 proposalId) private returns (ProposalState) {
        ProposalCore storage proposal = proposals[proposalId];
        if (block.timestamp > proposal.deadline) {
            if (proposal.votesFor > proposal.votesAgainst) {
                return ProposalState.Passed;
            } else {
                return ProposalState.Failed;
            }
        }
        return ProposalState.Active;
    }

    /// @notice checks to see if quorum has been reached for a proposal
    function _quorumReached(uint256 proposalId) private view returns (bool) {
        ProposalCore storage proposal = proposals[proposalId];
        // can't have zero votes reach quota
        if (proposal.votesFor + proposal.votesAgainst == 0) {
            return false;
        }
        bool votesAboveQuota = (proposal.votesFor + proposal.votesAgainst) * 4 >= proposal.totalEligibleVoters;
        bool votingPeriodConcluded = block.timestamp > proposal.deadline;
        if (votesAboveQuota && votingPeriodConcluded) {
            return true;
        }
        return false;
    }

    /// @notice gets the associated chain id
    function _getChainId() private view returns (uint256) {
        uint chainId;
        assembly {chainId := chainid()}
        return chainId;
    }

    /// @notice Purchases an NFT for the DAO
    /// @param marketplace The address of the INftMarketplace
    /// @param nftContract The address of the NFT contract to purchase
    /// @param nftId The token ID on the nftContract to purchase
    /// @param maxPrice The price above which the NFT is deemed too expensive
    /// and this function call should fail
    function buyNFTFromMarketplace(
        INftMarketplace marketplace,
        address nftContract,
        uint256 nftId,
        uint256 maxPrice
    ) external {
        require(msg.sender == address(this), "ONLY_DAO");
        uint256 nftPrice = marketplace.getPrice(nftContract, nftId);
        if (nftPrice <= maxPrice) {
            bool success = marketplace.buy{value: nftPrice}(nftContract, nftId);
            require(success, "purchase failed");
        } else {
            revert('too expensive');
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
