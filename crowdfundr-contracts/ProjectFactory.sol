//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import './Project.sol';

contract ProjectFactory {
    event ProjectCreated(address creator, address newProject);
    Project[] public allProjects;

    function create(address _creator, string memory _name, string memory _symbol, uint256 _goal) external {
        Project newProject = new Project(_creator, _name, _symbol, _goal);
        allProjects.push(newProject);
        emit ProjectCreated(msg.sender, address(newProject));
    }

    function getProjects() public view returns (Project[] memory) {
        return allProjects;
    }

}
