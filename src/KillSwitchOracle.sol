// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { Ownable }       from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { EnumerableSet } from "lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import { AggregatorInterface }  from "lib/aave-v3-core/contracts/dependencies/chainlink/AggregatorInterface.sol";
import { IPool }                from "lib/aave-v3-core/contracts/interfaces/IPool.sol";
import { IPoolConfigurator }    from "lib/aave-v3-core/contracts/interfaces/IPoolConfigurator.sol";
import { ReserveConfiguration } from "lib/aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes }            from "lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

contract KillSwitchOracle is Ownable {

    using EnumerableSet        for EnumerableSet.AddressSet;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /******************************************************************************************************************/
    /*** Events                                                                                                     ***/
    /******************************************************************************************************************/

    event SetOracle(address oracle, uint256 threshold);
    event DisableOracle(address oracle);
    event Trigger(address oracle, uint256 threshold, uint256 price);
    event AssetLTV0(address asset);
    event AssetFrozen(address asset);
    event Reset();

    /******************************************************************************************************************/
    /*** Declarations and Constructor                                                                               ***/
    /******************************************************************************************************************/

    IPool             public immutable pool;
    IPoolConfigurator public immutable poolConfigurator;

    bool public inLockdown;

    EnumerableSet.AddressSet private _oracles;

    mapping(address => uint256) public oracleThresholds;

    constructor(
        IPool _pool,
        IPoolConfigurator _poolConfigurator
    ) Ownable(msg.sender) {
        pool             = _pool;
        poolConfigurator = _poolConfigurator;
    }

    /******************************************************************************************************************/
    /*** Owner Functions                                                                                            ***/
    /******************************************************************************************************************/

    function setOracle(address oracle, uint256 threshold) external onlyOwner {
        oracleThresholds[oracle] = threshold;
        _oracles.add(oracle);  // It's okay to add the same oracle multiple times

        emit SetOracle(oracle, threshold);
    }

    function disableOracle(address oracle) external onlyOwner {
        require(oracleThresholds[oracle] != 0, "KillSwitchOracle/does-not-exist");

        _oracles.remove(oracle);
        delete oracleThresholds[oracle];

        emit DisableOracle(oracle);
    }

    function reset() external onlyOwner {
        require(inLockdown, "KillSwitchOracle/not-in-lockdown");

        inLockdown = false;

        emit Reset();
    }

    /******************************************************************************************************************/
    /*** Getter Functions                                                                                           ***/
    /******************************************************************************************************************/

    function numOracles() external view returns (uint256) {
        return _oracles.length();
    }
    function oracleAt(uint256 index) external view returns (address) {
        return _oracles.at(index);
    }
    function hasOracle(address oracle) external view returns (bool) {
        return _oracles.contains(oracle);
    }
    function oracles() external view returns (address[] memory) {
        return _oracles.values();
    }

    /******************************************************************************************************************/
    /*** Public Functions                                                                                           ***/
    /******************************************************************************************************************/

    function trigger(address oracle) external {
        uint256 threshold = oracleThresholds[oracle];
        require(threshold != 0, "KillSwitchOracle/does-not-exist");

        int256 price = AggregatorInterface(oracle).latestAnswer();
        require(price > 0,                   "KillSwitchOracle/invalid-price");
        require(uint256(price) <= threshold, "KillSwitchOracle/price-not-below-bound");

        inLockdown = true;
        emit Trigger(oracle, threshold, uint256(price));

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

            uint256 ltv = config.getLtv();
            if (ltv > 0) {
                // This asset is being used as collateral
                // We only want to disable new borrows against this to allow users
                // to top up their positions to prevent getting liquidated
                poolConfigurator.configureReserveAsCollateral(
                    asset,
                    0,
                    config.getLiquidationThreshold(),
                    config.getLiquidationBonus()
                );

                emit AssetLTV0(asset);
            } else {
                // This is a borrow-only asset
                poolConfigurator.setReserveFreeze(asset, true);

                emit AssetFrozen(asset);
            }
        }
    }

}
