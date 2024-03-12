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
    event BorrowDisabled(address indexed asset);

    address constant POOL_ADDRESSES_PROVIDER = 0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE;
    address constant POOL                    = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    address constant POOL_CONFIGURATOR       = 0x542DBa469bdE58FAeE189ffB60C6b49CE60E0738;
    address constant ACL_MANAGER             = 0xdA135Cd78A086025BcdC87B038a1C462032b510C;
    address constant SPARK_PROXY             = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;

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

        killSwitchOracle = new KillSwitchOracle(POOL_ADDRESSES_PROVIDER);
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

        assertEq(_getBorrowEnabled(DAI),    true);
        assertEq(_getBorrowEnabled(SDAI),   false);
        assertEq(_getBorrowEnabled(USDC),   true);
        assertEq(_getBorrowEnabled(WETH),   true);
        assertEq(_getBorrowEnabled(WSTETH), true);
        assertEq(_getBorrowEnabled(WBTC),   true);
        assertEq(_getBorrowEnabled(GNO),    false);
        assertEq(_getBorrowEnabled(RETH),   true);
        assertEq(_getBorrowEnabled(USDT),   true);

        vm.expectEmit(address(killSwitchOracle));
        emit Trigger(address(STETH_ORACLE), 0.9999e18, 0.999599998787617000e18);
        vm.expectEmit(address(killSwitchOracle));
        emit BorrowDisabled(DAI);
        vm.expectEmit(address(killSwitchOracle));
        emit BorrowDisabled(USDC);
        vm.expectEmit(address(killSwitchOracle));
        emit BorrowDisabled(WETH);
        vm.expectEmit(address(killSwitchOracle));
        emit BorrowDisabled(WSTETH);
        vm.expectEmit(address(killSwitchOracle));
        emit BorrowDisabled(WBTC);
        vm.expectEmit(address(killSwitchOracle));
        emit BorrowDisabled(RETH);
        vm.expectEmit(address(killSwitchOracle));
        emit BorrowDisabled(USDT);
        vm.prank(randomUser);
        killSwitchOracle.trigger(STETH_ORACLE);

        assertEq(_getBorrowEnabled(DAI),    false);
        assertEq(_getBorrowEnabled(SDAI),   false);
        assertEq(_getBorrowEnabled(USDC),   false);
        assertEq(_getBorrowEnabled(WETH),   false);
        assertEq(_getBorrowEnabled(WSTETH), false);
        assertEq(_getBorrowEnabled(WBTC),   false);
        assertEq(_getBorrowEnabled(GNO),    false);
        assertEq(_getBorrowEnabled(RETH),   false);
        assertEq(_getBorrowEnabled(USDT),   false);
    }

    function _getBorrowEnabled(address asset) internal view returns (bool) {
        return pool.getConfiguration(asset).getBorrowingEnabled();
    }

    // TODO add some more specific checks to make sure existing users can top up collateral, repay loans and withdraw collateral.
    // Also demonstate that users can't be liquidate or anything weird.

}
