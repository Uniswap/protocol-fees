// SPDX-License-Identifier: AGPl-3.0-only
pragma solidity 0.8.29;

interface IL1ERC20Gateway {
  // Events
  event DepositInitiated(
    address l1Token,
    address indexed _from,
    address indexed _to,
    uint256 indexed _sequenceNumber,
    uint256 _amount
  );
  event TxToL2(address indexed _from, address indexed _to, uint256 indexed _seqNum, bytes _data);
  event WithdrawRedirected(
    address indexed from,
    address indexed to,
    uint256 indexed exitNum,
    bytes newData,
    bytes data,
    bool madeExternalCall
  );
  event WithdrawalFinalized(
    address l1Token,
    address indexed _from,
    address indexed _to,
    uint256 indexed _exitNum,
    uint256 _amount
  );
  event AdminChanged(address previousAdmin, address newAdmin);
  event BeaconUpgraded(address indexed beacon);
  event Upgraded(address indexed implementation);

  // Functions
  function calculateL2TokenAddress(address l1ERC20) external view returns (address);
  function cloneableProxyHash() external view returns (bytes32);
  function counterpartGateway() external view returns (address);
  function encodeWithdrawal(uint256 _exitNum, address _initialDestination)
    external
    pure
    returns (bytes32);
  function finalizeInboundTransfer(
    address _token,
    address _from,
    address _to,
    uint256 _amount,
    bytes memory _data
  ) external payable;
  function getExternalCall(uint256 _exitNum, address _initialDestination, bytes memory _initialData)
    external
    view
    returns (address target, bytes memory data);
  function getOutboundCalldata(
    address _token,
    address _from,
    address _to,
    uint256 _amount,
    bytes memory _data
  ) external view returns (bytes memory outboundCalldata);
  function inbox() external view returns (address);
  function initialize(
    address _l2Counterpart,
    address _router,
    address _inbox,
    bytes32 _cloneableProxyHash,
    address _l2BeaconProxyFactory
  ) external;
  function l2BeaconProxyFactory() external view returns (address);
  function outboundTransfer(
    address _l1Token,
    address _to,
    uint256 _amount,
    uint256 _maxGas,
    uint256 _gasPriceBid,
    bytes memory _data
  ) external payable returns (bytes memory res);
  function outboundTransferCustomRefund(
    address _l1Token,
    address _refundTo,
    address _to,
    uint256 _amount,
    uint256 _maxGas,
    uint256 _gasPriceBid,
    bytes memory _data
  ) external payable returns (bytes memory res);
  function postUpgradeInit() external;
  function redirectedExits(bytes32)
    external
    view
    returns (bool isExit, address _newTo, bytes memory _newData);
  function router() external view returns (address);
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
  function transferExitAndCall(
    uint256 _exitNum,
    address _initialDestination,
    address _newDestination,
    bytes memory _newData,
    bytes memory _data
  ) external;
  function whitelist() external view returns (address);
}

interface IArbitrumOrbitResourceFirepit {
  function L2_GATEWAY_ROUTER() external pure returns (address);
}
