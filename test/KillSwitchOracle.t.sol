// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { IPool }                from "lib/aave-v3-core/contracts/interfaces/IPool.sol";
import { ReserveConfiguration } from "lib/aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes }            from "lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import { MockOracle }                from "test/mocks/MockOracle.sol";
import { MockPool }                  from "test/mocks/MockPool.sol";
import { MockPoolAddressesProvider } from "test/mocks/MockPoolAddressesProvider.sol";
import { MockPoolConfigurator }      from "test/mocks/MockPoolConfigurator.sol";

import { KillSwitchOracle } from "src/KillSwitchOracle.sol";

contract KillSwitchOracleTest is Test {

    struct ReserveConfigParams {
        address asset;
        bool    active;
        bool    frozen;
        bool    paused;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
    }

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    event SetOracle(address indexed oracle, uint256 threshold);
    event DisableOracle(address indexed oracle);
    event Trigger(address indexed oracle, uint256 threshold, uint256 price);
    event AssetLTV0(address indexed asset);
    event AssetFrozen(address indexed asset);
    event Reset();

    MockPoolAddressesProvider poolAddressesProvider;
    MockPool                  pool;
    MockPoolConfigurator      poolConfigurator;
    MockOracle                oracle;
    MockOracle                anotherOracle;

    KillSwitchOracle killSwitchOracle;

    address owner         = makeAddr("owner");
    address randomAddress = makeAddr("randomAddress");

    address asset1 = makeAddr("asset1");
    address asset2 = makeAddr("asset2");
    address asset3 = makeAddr("asset3");
    address asset4 = makeAddr("asset4");
    address asset5 = makeAddr("asset5");

    function setUp() public {
        pool                  = new MockPool();
        poolConfigurator      = new MockPoolConfigurator(IPool(address(pool)));
        poolAddressesProvider = new MockPoolAddressesProvider(address(pool), address(poolConfigurator));
        oracle                = new MockOracle(1e8);
        anotherOracle         = new MockOracle(1e8);

        killSwitchOracle = new KillSwitchOracle(address(poolAddressesProvider));
        killSwitchOracle.transferOwnership(owner);
    }

    function test_constructor() public {
        assertEq(address(killSwitchOracle.pool()),             address(pool));
        assertEq(address(killSwitchOracle.poolConfigurator()), address(poolConfigurator));
        assertEq(killSwitchOracle.triggered(),                 false);
        assertEq(killSwitchOracle.numOracles(),                0);
    }

    function test_owner() public {
        killSwitchOracle = new KillSwitchOracle(address(poolAddressesProvider));
        assertEq(killSwitchOracle.owner(), address(this));
        killSwitchOracle.transferOwnership(owner);
        assertEq(killSwitchOracle.owner(), owner);
    }

    function test_setOracle_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", randomAddress));
        vm.prank(randomAddress);
        killSwitchOracle.setOracle(address(oracle), 0.99e8);
    }

    function test_setOracle_thresholdZero() public {
        vm.expectRevert("KillSwitchOracle/invalid-threshold");
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 0);
    }

    function test_setOracle_thresholdSame() public {
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 0.99e8);

        vm.expectRevert("KillSwitchOracle/invalid-threshold");
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 0.99e8);
    }

    function test_setOracle() public {
        assertEq(killSwitchOracle.numOracles(),                      0);
        assertEq(killSwitchOracle.oracleThresholds(address(oracle)), 0);

        vm.expectEmit(address(killSwitchOracle));
        emit SetOracle(address(oracle), 0.99e8);
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 0.99e8);

        assertEq(killSwitchOracle.numOracles(),                      1);
        assertEq(killSwitchOracle.oracleAt(0),                       address(oracle));
        assertEq(killSwitchOracle.oracleThresholds(address(oracle)), 0.99e8);
    }

    function test_setOracle_twice() public {
        assertEq(killSwitchOracle.numOracles(),                      0);
        assertEq(killSwitchOracle.oracleThresholds(address(oracle)), 0);

        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 0.99e8);

        assertEq(killSwitchOracle.numOracles(),                      1);
        assertEq(killSwitchOracle.oracleAt(0),                       address(oracle));
        assertEq(killSwitchOracle.oracleThresholds(address(oracle)), 0.99e8);

        // Should only update the threshold
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 0.98e8);

        assertEq(killSwitchOracle.numOracles(),                      1);
        assertEq(killSwitchOracle.oracleAt(0),                       address(oracle));
        assertEq(killSwitchOracle.oracleThresholds(address(oracle)), 0.98e8);
    }

    function test_disableOracle_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", randomAddress));
        vm.prank(randomAddress);
        killSwitchOracle.disableOracle(address(oracle));
    }

    function test_disableOracle_notSet() public {
        vm.expectRevert("KillSwitchOracle/oracle-does-not-exist");
        vm.prank(owner);
        killSwitchOracle.disableOracle(address(oracle));
    }

    function test_disableOracle() public {
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 0.99e8);

        assertEq(killSwitchOracle.numOracles(),                      1);
        assertEq(killSwitchOracle.oracleAt(0),                       address(oracle));
        assertEq(killSwitchOracle.oracleThresholds(address(oracle)), 0.99e8);

        vm.expectEmit(address(killSwitchOracle));
        emit DisableOracle(address(oracle));
        vm.prank(owner);
        killSwitchOracle.disableOracle(address(oracle));

        assertEq(killSwitchOracle.numOracles(),                      0);
        assertEq(killSwitchOracle.oracleThresholds(address(oracle)), 0);
    }

    function test_reset_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", randomAddress));
        vm.prank(randomAddress);
        killSwitchOracle.reset();
    }

    function test_reset_notTriggered() public {
        vm.expectRevert("KillSwitchOracle/not-triggered");
        vm.prank(owner);
        killSwitchOracle.reset();
    }

    function test_reset() public {
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 1e8);
        killSwitchOracle.trigger(address(oracle));
        
        assertEq(killSwitchOracle.triggered(), true);
        
        vm.expectEmit(address(killSwitchOracle));
        emit Reset();
        vm.prank(owner);
        killSwitchOracle.reset();

        assertEq(killSwitchOracle.triggered(), false);
    }

    function test_oracles() public {
        address[] memory oracles = killSwitchOracle.oracles();
        assertEq(oracles.length,                                     0);
        assertEq(killSwitchOracle.numOracles(),                      0);
        assertEq(killSwitchOracle.hasOracle(address(oracle)),        false);
        assertEq(killSwitchOracle.hasOracle(address(anotherOracle)), false);
        assertEq(killSwitchOracle.hasOracle(randomAddress),          false);

        vm.startPrank(owner);
        killSwitchOracle.setOracle(address(oracle),        1e8);
        killSwitchOracle.setOracle(address(anotherOracle), 1e8);
        vm.stopPrank();

        oracles = killSwitchOracle.oracles();
        assertEq(oracles.length,                                     2);
        assertEq(oracles[0],                                         address(oracle));
        assertEq(oracles[1],                                         address(anotherOracle));
        assertEq(killSwitchOracle.numOracles(),                      2);
        assertEq(killSwitchOracle.oracleAt(0),                       address(oracle));
        assertEq(killSwitchOracle.oracleAt(1),                       address(anotherOracle));
        assertEq(killSwitchOracle.hasOracle(address(oracle)),        true);
        assertEq(killSwitchOracle.hasOracle(address(anotherOracle)), true);
        assertEq(killSwitchOracle.hasOracle(randomAddress),          false);

        vm.prank(owner);
        killSwitchOracle.disableOracle(address(oracle));

        oracles = killSwitchOracle.oracles();
        assertEq(oracles.length,                                     1);
        assertEq(oracles[0],                                         address(anotherOracle));
        assertEq(killSwitchOracle.numOracles(),                      1);
        assertEq(killSwitchOracle.oracleAt(0),                       address(anotherOracle));
        assertEq(killSwitchOracle.hasOracle(address(oracle)),        false);
        assertEq(killSwitchOracle.hasOracle(address(anotherOracle)), true);
        assertEq(killSwitchOracle.hasOracle(randomAddress),          false);
    }

    function test_trigger_alreadyTriggered() public {
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 1e8);
        killSwitchOracle.trigger(address(oracle));

        vm.expectRevert("KillSwitchOracle/already-triggered");
        killSwitchOracle.trigger(address(oracle));
    }

    function test_trigger_doesNotExist() public {
        vm.prank(owner);
        vm.expectRevert("KillSwitchOracle/oracle-does-not-exist");
        killSwitchOracle.trigger(address(oracle));
    }

    function test_trigger_invalidPrice() public {
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 1e8);

        oracle.setLatestAnswer(-1);
        vm.expectRevert("KillSwitchOracle/invalid-price");
        killSwitchOracle.trigger(address(oracle));

        oracle.setLatestAnswer(0);
        vm.expectRevert("KillSwitchOracle/invalid-price");
        killSwitchOracle.trigger(address(oracle));
    }

    function test_trigger_priceAboveThreshold() public {
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 0.99e8);

        vm.expectRevert("KillSwitchOracle/price-above-threshold");
        killSwitchOracle.trigger(address(oracle));
    }

    function test_trigger() public {
        ReserveConfigParams[5] memory params = [
            // Collateral asset (Ex. ETH, wstETH, sDAI, etc)
            ReserveConfigParams({
                asset:                asset1,
                active:               true,
                frozen:               false,
                paused:               false,
                ltv:                  80_00,
                liquidationThreshold: 83_00,
                liquidationBonus:     105_00
            }),
            // Borrow-only asset (Ex. DAI, USDC, etc)
            ReserveConfigParams({
                asset:                asset2,
                active:               true,
                frozen:               false,
                paused:               false,
                ltv:                  0,
                liquidationThreshold: 0,
                liquidationBonus:     0
            }),
            // Frozen/LTV0 asset (Ex. GNO)
            ReserveConfigParams({
                asset:                asset3,
                active:               true,
                frozen:               true,
                paused:               false,
                ltv:                  0,
                liquidationThreshold: 25_00,
                liquidationBonus:     110_00
            }),
            // Paused asset
            ReserveConfigParams({
                asset:                asset4,
                active:               true,
                frozen:               false,
                paused:               true,
                ltv:                  80_00,
                liquidationThreshold: 83_00,
                liquidationBonus:     105_00
            }),
            // Inactive asset
            ReserveConfigParams({
                asset:                asset5,
                active:               false,
                frozen:               false,
                paused:               false,
                ltv:                  0,
                liquidationThreshold: 0,
                liquidationBonus:     0
            })
        ];

        for (uint256 i = 0; i < params.length; i++) {
            _initReserve(params[i]);
        }

        assertEq(pool.getReservesList().length, 5);

        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 0.99e8);
        oracle.setLatestAnswer(0.98e8);

        vm.expectEmit(address(killSwitchOracle));
        emit Trigger(address(oracle), 0.99e8, 0.98e8);
        vm.expectEmit(address(killSwitchOracle));
        emit AssetLTV0(asset1);
        vm.expectEmit(address(killSwitchOracle));
        emit AssetFrozen(asset2);
        vm.prank(randomAddress);  // Permissionless call
        killSwitchOracle.trigger(address(oracle));

        params[0].ltv = 0;
        params[1].frozen = true;

        for (uint256 i = 0; i < params.length; i++) {
            _assertReserve(params[i]);
        }
    }

    function _initReserve(ReserveConfigParams memory params) internal {
        DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(params.asset);
        configuration.setActive(params.active);
        configuration.setFrozen(params.frozen);
        configuration.setPaused(params.paused);
        configuration.setLtv(params.ltv);
        configuration.setLiquidationThreshold(params.liquidationThreshold);
        configuration.setLiquidationBonus(params.liquidationBonus);
        pool.__addReserve(params.asset, configuration);
    }

    function _assertReserve(ReserveConfigParams memory params) internal {
        DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(params.asset);
        assertEq(configuration.getActive(),               params.active);
        assertEq(configuration.getFrozen(),               params.frozen);
        assertEq(configuration.getPaused(),               params.paused);
        assertEq(configuration.getLtv(),                  params.ltv);
        assertEq(configuration.getLiquidationThreshold(), params.liquidationThreshold);
        assertEq(configuration.getLiquidationBonus(),     params.liquidationBonus);
    }
    
}
