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

    event AddFreezeAsset(address asset);
    event RemoveFreezeAsset(address asset);
    event AddCollateralAsset(address asset);
    event RemoveCollateralAsset(address asset);
    event SetOracle(address oracle, uint256 threshold);
    event DisableOracle(address oracle);
    event Trigger(address oracle, uint256 threshold, uint256 price);
    event Reset();

    /******************************************************************************************************************/
    /*** Declarations and Constructor                                                                               ***/
    /******************************************************************************************************************/

    IPool             public immutable pool;
    IPoolConfigurator public immutable poolConfigurator;

    bool public inLockdown;

    EnumerableSet.AddressSet private _freezeAssets;
    EnumerableSet.AddressSet private _collateralAssets;
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

    function addFreezeAsset(address asset) external onlyOwner {
        require(_freezeAssets.add(asset), "KillSwitchOracle/already-exists");

        emit AddFreezeAsset(asset);
    }

    function removeFreezeAsset(address asset) external onlyOwner {
        require(_freezeAssets.remove(asset), "KillSwitchOracle/does-not-exist");

        emit RemoveFreezeAsset(asset);
    }

    function addCollateralAsset(address asset) external onlyOwner {
        require(_collateralAssets.add(asset), "KillSwitchOracle/already-exists");

        emit AddCollateralAsset(asset);
    }

    function removeCollateralAsset(address asset) external onlyOwner {
        require(_collateralAssets.remove(asset), "KillSwitchOracle/does-not-exist");

        emit RemoveCollateralAsset(asset);
    }

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

    function numFreezeAssets() external view returns (uint256) {
        return _freezeAssets.length();
    }
    function freezeAssetAt(uint256 index) external view returns (address) {
        return _freezeAssets.at(index);
    }
    function hasFreezeAsset(address asset) external view returns (bool) {
        return _freezeAssets.contains(asset);
    }
    function freezeAssets() external view returns (address[] memory) {
        return _freezeAssets.values();
    }

    function numCollateralAssets() external view returns (uint256) {
        return _collateralAssets.length();
    }
    function collateralAssetAt(uint256 index) external view returns (address) {
        return _collateralAssets.at(index);
    }
    function hasCollateralAsset(address asset) external view returns (bool) {
        return _collateralAssets.contains(asset);
    }
    function collateralAssets() external view returns (address[] memory) {
        return _collateralAssets.values();
    }

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

        for (uint256 i = 0; i < _freezeAssets.length(); i++) {
            poolConfigurator.setReserveFreeze(_freezeAssets.at(i), true);
        }
        for (uint256 i = 0; i < _collateralAssets.length(); i++) {
            address asset = _collateralAssets.at(i);
            DataTypes.ReserveConfigurationMap memory currentConfig = pool.getConfiguration(asset);
            poolConfigurator.configureReserveAsCollateral(
                asset,
                0,
                currentConfig.getLiquidationThreshold(),
                currentConfig.getLiquidationBonus()
            );
        }

        emit Trigger(oracle, threshold, uint256(price));
    }

}
