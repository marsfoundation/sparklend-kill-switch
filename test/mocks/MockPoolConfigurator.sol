// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import { IPool }                from "lib/aave-v3-core/contracts/interfaces/IPool.sol";
import { ReserveConfiguration } from "lib/aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes }            from "lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

contract MockPoolConfigurator {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    IPool public pool;

    constructor(IPool _pool) {
        pool = _pool;
    }

    function setReserveBorrowing(address asset, bool borrowEnabled) external {
        DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(asset);
        configuration.setBorrowingEnabled(borrowEnabled);
        pool.setConfiguration(asset, configuration);
    }

}
