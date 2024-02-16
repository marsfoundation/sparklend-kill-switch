// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { Ownable }       from "openzeppelin-contracts/access/Ownable.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

contract KillSwitchOracle is Ownable {

    using EnumerableSet for EnumerableSet.AddressSet;

    /******************************************************************************************************************/
    /*** Events                                                                                                     ***/
    /******************************************************************************************************************/

    event AddFreezeAsset(address asset);
    event RemoveFreezeAsset(address asset);
    event AddCollateralAsset(address asset);
    event RemoveCollateralAsset(address asset);
    event SetOracle(address oracle, uint256 lowerPriceBound);
    event DisableOracle(address oracle);
    event Trigger();
    event Reset();

    /******************************************************************************************************************/
    /*** Declarations and Constructor                                                                               ***/
    /******************************************************************************************************************/

    bool public inLockdown;

    EnumerableSet.AddressSet private _freezeAssets;
    EnumerableSet.AddressSet private _collateralAssets;

    mapping(address => uint256) public oracles;

    constructor() Ownable(msg.sender) {
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

    function setOracle(address oracle, uint256 lowerPriceBound) external onlyOwner {
        oracles[oracle] = lowerPriceBound;

        emit SetOracle(oracle, lowerPriceBound);
    }

    function disableOracle(address oracle) external onlyOwner {
        require(oracles[oracle] != 0, "KillSwitchOracle/does-not-exist");

        delete oracles[oracle];

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
    function freezeAssetsAt(uint256 index) external view returns (address) {
        return _freezeAssets.at(index);
    }
    function hasFreezeAsset(address domain) external view returns (bool) {
        return _freezeAssets.contains(domain);
    }
    function freezeAssets() external view returns (address[] memory) {
        return _freezeAssets.values();
    }

    function numCollateralAssets() external view returns (uint256) {
        return _collateralAssets.length();
    }
    function collateralAssetsAt(uint256 index) external view returns (address) {
        return _collateralAssets.at(index);
    }
    function hasCollateralAsset(address domain) external view returns (bool) {
        return _collateralAssets.contains(domain);
    }
    function collateralAssets() external view returns (address[] memory) {
        return _collateralAssets.values();
    }

    /******************************************************************************************************************/
    /*** Public Functions                                                                                           ***/
    /******************************************************************************************************************/

    function trigger(address oracle) external {
        require(_freezeAssets.add(asset), "KillSwitchOracle/already-exists");
    }

}
