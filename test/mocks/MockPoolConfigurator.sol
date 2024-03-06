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

    function configureReserveAsCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external {
        DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(asset);
        configuration.setLtv(ltv);
        configuration.setLiquidationThreshold(liquidationThreshold);
        configuration.setLiquidationBonus(liquidationBonus);
        pool.setConfiguration(asset, configuration);
    }

    function setReserveFreeze(address asset, bool freeze) external {
        DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(asset);
        configuration.setFrozen(freeze);
        pool.setConfiguration(asset, configuration);
    }

}
