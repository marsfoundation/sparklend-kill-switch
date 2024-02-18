// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import { ReserveConfiguration } from "lib/aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes }            from "lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

contract MockPool {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address[] private reserves;
    mapping(address => DataTypes.ReserveConfigurationMap) private configurations;

    constructor() {
    }

    function getReservesList() external view returns (address[] memory) {
        return reserves;
    }

    function __addReserve(address asset, DataTypes.ReserveConfigurationMap memory configuration) external {
        reserves.push(asset);
        configurations[asset] = configuration;
    }

    function getConfiguration(address asset) external view returns (DataTypes.ReserveConfigurationMap memory) {
        return configurations[asset];
    }

    function setConfiguration(address asset, DataTypes.ReserveConfigurationMap memory configuration) external {
        configurations[asset] = configuration;
    }

}
