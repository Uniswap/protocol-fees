// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {SoftNonce, Nonce} from "../../src/base/Nonce.sol";

contract MockSoftNonce is SoftNonce {
  function setNonce(uint256 _nonce) external {
    nonce = _nonce;
  }

  function mock(uint256 _nonce) external handleSoftNonce(_nonce) returns (bool) {
    return true;
  }
}

contract SoftNonceTest is Test {
  MockSoftNonce public mockSoftNonce;

  function setUp() public {
    mockSoftNonce = new MockSoftNonce();
  }

  /// @dev happy path - calldata nonce matches the current nonce
  function test_equal(uint256 startingNonce) public {
    startingNonce = bound(startingNonce, 0, type(uint256).max - 2);
    mockSoftNonce.setNonce(startingNonce);
    assertTrue(mockSoftNonce.mock(mockSoftNonce.nonce()));
    assertTrue(mockSoftNonce.mock(mockSoftNonce.nonce()));
  }

  /// @dev happy path - revert when using the incorrect nonce
  function test_revert_invalidNonce(uint256 startingNonce, uint256 calldataNonce) public {
    startingNonce = bound(startingNonce, 0, type(uint256).max - 1);
    vm.assume(calldataNonce != startingNonce);

    mockSoftNonce.setNonce(startingNonce);
    vm.expectRevert(Nonce.InvalidNonce.selector);
    mockSoftNonce.mock(calldataNonce);
  }

  function test_revert_spentNonce(uint256 startingNonce) public {
    startingNonce = bound(startingNonce, 0, type(uint256).max - 1);
    mockSoftNonce.setNonce(startingNonce);

    // Use the nonce
    assertTrue(mockSoftNonce.mock(mockSoftNonce.nonce()));

    // Attempt to use the same nonce again
    vm.expectRevert(Nonce.InvalidNonce.selector);
    mockSoftNonce.mock(startingNonce);
  }

  /// @dev an expired nonce does not revert
  function test_expired_nonce(uint256 calldataNonce) public {
    uint256 initialNonce = mockSoftNonce.nonce();
    vm.assume(calldataNonce != initialNonce);

    vm.expectRevert(Nonce.InvalidNonce.selector);
    mockSoftNonce.mock(calldataNonce);

    // Simulate the expiration of the nonce
    skip(mockSoftNonce.EXPIRATION() + 1);
    assertTrue(mockSoftNonce.mock(calldataNonce));
  }
}
