// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { IPool }             from "lib/aave-v3-core/contracts/interfaces/IPool.sol";
import { IPoolConfigurator } from "lib/aave-v3-core/contracts/interfaces/IPoolConfigurator.sol";

import { MockOracle }             from "test/mocks/MockOracle.sol";
import { MockPool }             from "test/mocks/MockPool.sol";
import { MockPoolConfigurator } from "test/mocks/MockPoolConfigurator.sol";

import { KillSwitchOracle } from "src/KillSwitchOracle.sol";

contract KillSwitchOracleTest is Test {

    MockPool             pool;
    MockPoolConfigurator poolConfigurator;
    MockOracle           oracle;
    MockOracle           anotherOracle;

    KillSwitchOracle killSwitchOracle;

    address owner         = makeAddr("owner");
    address randomAddress = makeAddr("randomAddress");

    function setUp() public {
        pool             = new MockPool();
        poolConfigurator = new MockPoolConfigurator(IPool(address(pool)));
        oracle           = new MockOracle(1e8);
        anotherOracle    = new MockOracle(1e8);

        killSwitchOracle = new KillSwitchOracle(
            IPool(address(pool)),
            IPoolConfigurator(address(poolConfigurator))
        );
        killSwitchOracle.transferOwnership(owner);
    }

    function test_constructor() public {
        assertEq(address(killSwitchOracle.pool()),             address(pool));
        assertEq(address(killSwitchOracle.poolConfigurator()), address(poolConfigurator));
        assertEq(killSwitchOracle.triggered(),                 false);
        assertEq(killSwitchOracle.numOracles(),                0);
        assertEq(killSwitchOracle.owner(),                     owner);
    }

    function test_setOracle_revertOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", randomAddress));
        vm.prank(randomAddress);
        killSwitchOracle.setOracle(address(oracle), 0.99e8);
    }

    function test_setOracle() public {
        assertEq(killSwitchOracle.numOracles(),                      0);
        assertEq(killSwitchOracle.oracleThresholds(address(oracle)), 0);

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

    function test_disableOracle_revertOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", randomAddress));
        vm.prank(randomAddress);
        killSwitchOracle.disableOracle(address(oracle));
    }

    function test_disableOracle_revertNotSet() public {
        vm.expectRevert("KillSwitchOracle/does-not-exist");
        vm.prank(owner);
        killSwitchOracle.disableOracle(address(oracle));
    }

    function test_disableOracle() public {
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 0.99e8);

        assertEq(killSwitchOracle.numOracles(),                      1);
        assertEq(killSwitchOracle.oracleAt(0),                       address(oracle));
        assertEq(killSwitchOracle.oracleThresholds(address(oracle)), 0.99e8);

        vm.prank(owner);
        killSwitchOracle.disableOracle(address(oracle));

        assertEq(killSwitchOracle.numOracles(),                      0);
        assertEq(killSwitchOracle.oracleThresholds(address(oracle)), 0);
    }

    function test_reset_revertOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", randomAddress));
        vm.prank(randomAddress);
        killSwitchOracle.reset();
    }

    function test_reset_revertNotTriggered() public {
        vm.expectRevert("KillSwitchOracle/not-triggered");
        vm.prank(owner);
        killSwitchOracle.reset();
    }

    function test_reset() public {
        vm.prank(owner);
        killSwitchOracle.setOracle(address(oracle), 1e8);
        killSwitchOracle.trigger(address(oracle));
        
        assertEq(killSwitchOracle.triggered(), true);
        
        vm.prank(owner);
        killSwitchOracle.reset();

        assertEq(killSwitchOracle.triggered(), false);
    }

    function test_oracles() public {
        address[] memory oracles = killSwitchOracle.oracles();
        assertEq(oracles.length,                                      0);
        assertEq(killSwitchOracle.numOracles(),                       0);
        assertEq(killSwitchOracle.hasOracle(address(oracle)),        false);
        assertEq(killSwitchOracle.hasOracle(address(anotherOracle)), false);
        assertEq(killSwitchOracle.hasOracle(randomAddress),          false);

        vm.startPrank(owner);
        killSwitchOracle.setOracle(address(oracle), 1e8);
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
    
}
