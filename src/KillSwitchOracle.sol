// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import { Ownable }       from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { EnumerableSet } from "lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import { AggregatorInterface }    from "lib/aave-v3-core/contracts/dependencies/chainlink/AggregatorInterface.sol";
import { IPool }                  from "lib/aave-v3-core/contracts/interfaces/IPool.sol";
import { IPoolAddressesProvider } from "lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import { IPoolConfigurator }      from "lib/aave-v3-core/contracts/interfaces/IPoolConfigurator.sol";
import { ReserveConfiguration }   from "lib/aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes }              from "lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import { IKillSwitchOracle } from "src/interfaces/IKillSwitchOracle.sol";

contract KillSwitchOracle is IKillSwitchOracle, Ownable {

    using EnumerableSet        for EnumerableSet.AddressSet;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /******************************************************************************************************************/
    /*** Declarations and Constructor                                                                               ***/
    /******************************************************************************************************************/

    IPool             public override immutable pool;
    IPoolConfigurator public override immutable poolConfigurator;

    bool public override triggered;

    EnumerableSet.AddressSet private _oracles;

    mapping(address => uint256) public override oracleThresholds;

    constructor(address poolAddressesProvider) Ownable(msg.sender) {
        pool             = IPool(IPoolAddressesProvider(poolAddressesProvider).getPool());
        poolConfigurator = IPoolConfigurator(IPoolAddressesProvider(poolAddressesProvider).getPoolConfigurator());
    }

    /******************************************************************************************************************/
    /*** Owner Functions                                                                                            ***/
    /******************************************************************************************************************/

    function setOracle(address oracle, uint256 threshold) external override onlyOwner {
        require(threshold != 0 && threshold != oracleThresholds[oracle], "KillSwitchOracle/invalid-threshold");

        oracleThresholds[oracle] = threshold;

        // It's okay to add the same oracle multiple times
        // The EnumerableSet will make sure only 1 exists
        _oracles.add(oracle);  

        emit SetOracle(oracle, threshold);
    }

    function disableOracle(address oracle) external override onlyOwner {
        require(oracleThresholds[oracle] != 0, "KillSwitchOracle/oracle-does-not-exist");

        _oracles.remove(oracle);
        delete oracleThresholds[oracle];

        emit DisableOracle(oracle);
    }

    function reset() external override onlyOwner {
        require(triggered, "KillSwitchOracle/not-triggered");

        triggered = false;

        emit Reset();
    }

    /******************************************************************************************************************/
    /*** Getter Functions                                                                                           ***/
    /******************************************************************************************************************/

    function numOracles() external override view returns (uint256) {
        return _oracles.length();
    }

    function oracleAt(uint256 index) external override view returns (address) {
        return _oracles.at(index);
    }

    function hasOracle(address oracle) external override view returns (bool) {
        return _oracles.contains(oracle);
    }

    function oracles() external override view returns (address[] memory) {
        return _oracles.values();
    }

    /******************************************************************************************************************/
    /*** Public Functions                                                                                           ***/
    /******************************************************************************************************************/

    function trigger(address oracle) external override {
        // Once triggered, the kill switch can be used to disable all borrowing until it is reset
        if (!triggered) {
            uint256 threshold = oracleThresholds[oracle];
            require(threshold != 0, "KillSwitchOracle/oracle-does-not-exist");

            int256 price = AggregatorInterface(oracle).latestAnswer();
            require(price > 0,                   "KillSwitchOracle/invalid-price");
            require(uint256(price) <= threshold, "KillSwitchOracle/price-above-threshold");

            triggered = true;
            emit Trigger(oracle, threshold, uint256(price));
        }

        address[] memory assets = pool.getReservesList();
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(asset);

            // Skip all assets that are not active, frozen, or paused
            if (
                !config.getActive() ||
                config.getFrozen() ||
                config.getPaused()
            ) continue;

            if (config.getBorrowingEnabled()) {
                poolConfigurator.setReserveBorrowing(asset, false);

                emit BorrowDisabled(asset);
            }
        }
    }

}
