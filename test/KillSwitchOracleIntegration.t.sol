// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { AggregatorInterface }  from "lib/aave-v3-core/contracts/dependencies/chainlink/AggregatorInterface.sol";
import { IACLManager }          from "lib/aave-v3-core/contracts/interfaces/IACLManager.sol";
import { IPool }                from "lib/aave-v3-core/contracts/interfaces/IPool.sol";
import { IPoolConfigurator }    from "lib/aave-v3-core/contracts/interfaces/IPoolConfigurator.sol";
import { ReserveConfiguration } from "lib/aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes }            from "lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import { KillSwitchOracle } from "src/KillSwitchOracle.sol";

contract KillSwitchOracleIntegrationTest is Test {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    event Trigger(address indexed oracle, uint256 threshold, uint256 price);
    event AssetLTV0(address indexed asset);
    event AssetFrozen(address indexed asset);

    address constant POOL              = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    address constant POOL_CONFIGURATOR = 0x542DBa469bdE58FAeE189ffB60C6b49CE60E0738;
    address constant ACL_MANAGER       = 0xdA135Cd78A086025BcdC87B038a1C462032b510C;
    address constant SPARK_PROXY       = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;

    address constant WBTC_ORACLE  = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
    address constant STETH_ORACLE = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    address constant DAI    = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant SDAI   = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address constant USDC   = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH   = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant WBTC   = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant GNO    = 0x6810e776880C02933D47DB1b9fc05908e5386b96;
    address constant RETH   = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant USDT   = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    IPool             pool             = IPool(POOL);
    IPoolConfigurator poolConfigurator = IPoolConfigurator(POOL_CONFIGURATOR);
    IACLManager       aclManager       = IACLManager(ACL_MANAGER);

    address[] assets;

    address randomUser = makeAddr("randomUser");

    KillSwitchOracle public killSwitchOracle;

    function setUp() public {
        vm.createSelectFork(getChain("mainnet").rpcUrl, 19255277);  // Feb 18, 2024

        killSwitchOracle = new KillSwitchOracle(pool, poolConfigurator);
        killSwitchOracle.transferOwnership(SPARK_PROXY);

        vm.prank(SPARK_PROXY);
        aclManager.addRiskAdmin(address(killSwitchOracle));

        assets = pool.getReservesList();

        // Add oracles for the pegged assets
        // TODO: want to add reth too, but need to divide by exchange rate
        assertEq(AggregatorInterface(WBTC_ORACLE).latestAnswer(),  0.99968767e8);
        assertEq(AggregatorInterface(STETH_ORACLE).latestAnswer(), 0.999599998787617000e18);

        vm.startPrank(SPARK_PROXY);
        killSwitchOracle.setOracle(WBTC_ORACLE,  0.95e8);
        killSwitchOracle.setOracle(STETH_ORACLE, 0.9999e18);  // Should be lower in production, but we want to trigger the kill switch
        vm.stopPrank();
    }

    function test_trigger() public {
        vm.expectRevert("KillSwitchOracle/price-above-threshold");
        vm.prank(randomUser);
        killSwitchOracle.trigger(WBTC_ORACLE);

        _assertReserve({
            asset:                DAI,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 1,
            liquidationBonus:     104_50
        });
        _assertReserve({
            asset:                SDAI,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  74_00,
            liquidationThreshold: 76_00,
            liquidationBonus:     104_50
        });
        _assertReserve({
            asset:                USDC,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 0,
            liquidationBonus:     0
        });
        _assertReserve({
            asset:                WETH,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  80_00,
            liquidationThreshold: 82_50,
            liquidationBonus:     105_00
        });
        _assertReserve({
            asset:                WSTETH,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  68_50,
            liquidationThreshold: 79_50,
            liquidationBonus:     107_00
        });
        _assertReserve({
            asset:                WBTC,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  70_00,
            liquidationThreshold: 75_00,
            liquidationBonus:     107_00
        });
        _assertReserve({
            asset:                GNO,
            active:               true,
            frozen:               true,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 25_00,
            liquidationBonus:     110_00
        });
        _assertReserve({
            asset:                RETH,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  68_50,
            liquidationThreshold: 79_50,
            liquidationBonus:     107_00
        });
        _assertReserve({
            asset:                USDT,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 0,
            liquidationBonus:     0
        });

        vm.expectEmit(address(killSwitchOracle));
        emit Trigger(address(STETH_ORACLE), 0.9999e18, 0.999599998787617000e18);
        vm.expectEmit(address(killSwitchOracle));
        emit AssetFrozen(DAI);
        vm.expectEmit(address(killSwitchOracle));
        emit AssetLTV0(SDAI);
        vm.expectEmit(address(killSwitchOracle));
        emit AssetFrozen(USDC);
        vm.expectEmit(address(killSwitchOracle));
        emit AssetLTV0(WETH);
        vm.expectEmit(address(killSwitchOracle));
        emit AssetLTV0(WSTETH);
        vm.expectEmit(address(killSwitchOracle));
        emit AssetLTV0(WBTC);
        vm.expectEmit(address(killSwitchOracle));
        emit AssetLTV0(RETH);
        vm.expectEmit(address(killSwitchOracle));
        emit AssetFrozen(USDT);
        vm.prank(randomUser);
        killSwitchOracle.trigger(STETH_ORACLE);

        _assertReserve({
            asset:                DAI,
            active:               true,
            frozen:               true,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 1,
            liquidationBonus:     104_50
        });
        _assertReserve({
            asset:                SDAI,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 76_00,
            liquidationBonus:     104_50
        });
        _assertReserve({
            asset:                USDC,
            active:               true,
            frozen:               true,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 0,
            liquidationBonus:     0
        });
        _assertReserve({
            asset:                WETH,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 82_50,
            liquidationBonus:     105_00
        });
        _assertReserve({
            asset:                WSTETH,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 79_50,
            liquidationBonus:     107_00
        });
        _assertReserve({
            asset:                WBTC,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 75_00,
            liquidationBonus:     107_00
        });
        _assertReserve({
            asset:                GNO,
            active:               true,
            frozen:               true,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 25_00,
            liquidationBonus:     110_00
        });
        _assertReserve({
            asset:                RETH,
            active:               true,
            frozen:               false,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 79_50,
            liquidationBonus:     107_00
        });
        _assertReserve({
            asset:                USDT,
            active:               true,
            frozen:               true,
            paused:               false,
            ltv:                  0,
            liquidationThreshold: 0,
            liquidationBonus:     0
        });
    }

    function _assertReserve(
        address asset,
        bool active,
        bool frozen,
        bool paused,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) internal {
        DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(asset);
        assertEq(configuration.getActive(),               active);
        assertEq(configuration.getFrozen(),               frozen);
        assertEq(configuration.getPaused(),               paused);
        assertEq(configuration.getLtv(),                  ltv);
        assertEq(configuration.getLiquidationThreshold(), liquidationThreshold);
        assertEq(configuration.getLiquidationBonus(),     liquidationBonus);
    }

    // TODO add some more specific checks to make sure existing users can top up collateral, repay loans and withdraw collateral.
    // Also demonstate that users can't be liquidate or anything weird.

}
