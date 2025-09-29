pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {VestingLib} from "../src/libraries/VestingLib.sol";

contract VestingLibTest is Test {
  using VestingLib for uint256;

  function test_sub_positive_positive() public pure {
    uint256 total = 100;
    int256 claimed = 10;
    uint256 result = total.sub(claimed);
    assertEq(result, 90);
  }

  function test_sub_positive_negative() public pure {
    uint256 total = 100;
    int256 claimed = -10;
    uint256 result = total.sub(claimed);
    assertEq(result, 110);
  }

  function test_sub_positive_zero() public pure {
    uint256 total = 100;
    int256 claimed = 0;
    uint256 result = total.sub(claimed);
    assertEq(result, 100);
  }

  function test_sub_zero_zero() public pure {
    uint256 total = 0;
    int256 claimed = 0;
    uint256 result = total.sub(claimed);
    assertEq(result, 0);
  }

  function test_sub_zero_negative() public pure {
    uint256 total = 0;
    int256 claimed = -10;
    uint256 result = total.sub(claimed);
    assertEq(result, 10);
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_sub_zero_positive_reverts() public {
    uint256 total = 0;
    int256 claimed = 10;
    vm.expectRevert();
    total.sub(claimed);
  }
}
