pragma solidity >=0.6.0 <0.8.0;

interface IUserWallet{

    function requestTransferV1(address dest, string calldata assetName, uint256 amount) external;

    function submitWithdrawV1(address dest, uint256 withdrawAmount, uint256 amountWithFee, string calldata assetName) external;
}