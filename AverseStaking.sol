// SPDX-License-Identifier: MIT
pragma solidity >= 0.7.0 < 0.9.0;
import '@openzeppelin/contracts/access/Ownable.sol';
interface IArenaverseNFT {
  function balanceOf(address _user) external view returns(uint256);
  function transferFrom(address _user1, address _user2, uint256 _tokenId) external;
  function ownerOf(uint256 _tokenId) external returns(address);
}
interface IAVERSE {
  function balanceOf(address _user) external view returns(uint256);
  function transferFrom(address _user1, address _user2, uint256 _amount) external;
  function transfer(address _user, uint256 _amount) external;  
}
contract AverseStaking is Ownable {
  IArenaverseNFT public arenaverseNFT;
  IAVERSE public averse;
  address public POOL_WALLET = 0xdDCB518ac5a11F92243AdA209951fcd6e0B18705;
  uint256 public NFTRewardRate = 600 * (10 ** 9);
  uint256 public tokenRewardRate = 125;
  uint256 public LOCK_PERIOD = 7 days;
  mapping(address => uint256) public harvests;
  mapping(address => uint256) public lastUpdate;
  mapping(uint => address) public ownerOfToken;
  mapping(address => uint) public stakeBalances;
  mapping(address => mapping(uint256 => uint256)) public ownedTokens;
  mapping(uint256 => uint256) public ownedTokensIndex;

  mapping(address => uint256) public harvestsFt;
  mapping(address => uint256) public lastUpdateFt;
  mapping(address => uint) public stakeBalancesFt;
  mapping(address => uint256) public lockTime;

  bool public paused;

  constructor(
    address nftAddr,
    address ftAddr
  ) {
    arenaverseNFT = IArenaverseNFT(nftAddr);
    averse = IAVERSE(ftAddr);
  }

  function batchStake(uint[] memory tokenIds) external payable {
    require(paused == false, "Staking finished");
    updateHarvest();
    for (uint256 i = 0; i < tokenIds.length; i++) {
      require(arenaverseNFT.ownerOf(tokenIds[i]) == msg.sender, 'you are not owner!');
      ownerOfToken[tokenIds[i]] = msg.sender;
      arenaverseNFT.transferFrom(msg.sender, address(this), tokenIds[i]);
      _addTokenToOwner(msg.sender, tokenIds[i]);
      stakeBalances[msg.sender]++;
    }
  }

  function batchWithdraw(uint[] memory tokenIds) external payable {    
    harvest();
    for (uint i = 0; i < tokenIds.length; i++) {
      require(ownerOfToken[tokenIds[i]] == msg.sender, "AverseStaking: Unable to withdraw");
      arenaverseNFT.transferFrom(address(this), msg.sender, tokenIds[i]);
      _removeTokenFromOwner(msg.sender, tokenIds[i]);
      stakeBalances[msg.sender]--;
    }
  }

  function batchWithdrawWithoutharvest(uint[] memory tokenIds) external payable {    
    for (uint i = 0; i < tokenIds.length; i++) {
      require(ownerOfToken[tokenIds[i]] == msg.sender, "AverseStaking: Unable to withdraw");
      arenaverseNFT.transferFrom(address(this), msg.sender, tokenIds[i]);
      _removeTokenFromOwner(msg.sender, tokenIds[i]);
      stakeBalances[msg.sender]--;
    }
  }

  function updateHarvest() internal {
    uint256 time = block.timestamp;
    uint256 timerFrom = lastUpdate[msg.sender];
    if (timerFrom > 0)
      harvests[msg.sender] += stakeBalances[msg.sender] * NFTRewardRate * (time - timerFrom) / 86400;
    lastUpdate[msg.sender] = time;
  }

  function harvest() public payable {
    updateHarvest();
    uint256 reward = harvests[msg.sender];
    if (reward > 0) {
      averse.transferFrom(POOL_WALLET, msg.sender, harvests[msg.sender]);
      harvests[msg.sender] = 0;
    }
  }

  function stakeOfOwner(address _owner)
  public
  view
  returns(uint256[] memory)
  {
    uint256 ownerTokenCount = stakeBalances[_owner];
    uint256[] memory tokenIds = new uint256[](ownerTokenCount);
    for (uint256 i; i < ownerTokenCount; i++) {
      tokenIds[i] = ownedTokens[_owner][i];
    }
    return tokenIds;
  }

  function getTotalClaimable(address _user) external view returns(uint256) {
    uint256 time = block.timestamp;
    uint256 pending = stakeBalances[msg.sender] * NFTRewardRate * (time - lastUpdate[_user]) / 86400;
    return harvests[_user] + pending;
  }

  function _addTokenToOwner(address to, uint256 tokenId) private {
      uint256 length = stakeBalances[to];
    ownedTokens[to][length] = tokenId;
    ownedTokensIndex[tokenId] = length;
  }
  
  function _removeTokenFromOwner(address from, uint256 tokenId) private {
      // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
      // then delete the last slot (swap and pop).

      uint256 lastTokenIndex = stakeBalances[from] - 1;
      uint256 tokenIndex = ownedTokensIndex[tokenId];

    // When the token to delete is the last token, the swap operation is unnecessary
    if (tokenIndex != lastTokenIndex) {
          uint256 lastTokenId = ownedTokens[from][lastTokenIndex];

      ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
      ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
    }

    // This also deletes the contents at the last position of the array
    delete ownedTokensIndex[tokenId];
    delete ownedTokens[from][lastTokenIndex];
  }

  function stakeFt(uint _amount) external payable {
    require(averse.balanceOf(msg.sender) > _amount, 'not enough token');
    require(stakeBalancesFt[msg.sender] == 0, 'already locked some part');
    updateHarvestFt();
    averse.transferFrom(msg.sender, address(this), _amount);
    stakeBalancesFt[msg.sender] += _amount;
    lockTime[msg.sender] = block.timestamp;
  }

  function withdrawFt(uint _amount) external payable {
    require(stakeBalancesFt[msg.sender] >= _amount, "CrocosFarm: Unable to withdraw Ft");
    require(lockTime[msg.sender] + LOCK_PERIOD <= block.timestamp, "You can't withdraw for 2 weeks.");
    harvestFt();
    averse.transferFrom(POOL_WALLET, msg.sender, _amount);
    stakeBalancesFt[msg.sender] -= _amount;
  }

  function updateHarvestFt() internal {
    uint256 time = block.timestamp;
    uint256 timerFrom = lastUpdateFt[msg.sender];
    if (timerFrom > 0)
      harvestsFt[msg.sender] += stakeBalancesFt[msg.sender] * tokenRewardRate * (time - timerFrom) / 86400 /10000;
    lastUpdateFt[msg.sender] = time;
  }

  function harvestFt() public payable {
    require(lockTime[msg.sender] + LOCK_PERIOD <= block.timestamp, "You can't withdraw Yourfor 2 weeks.");
    updateHarvestFt();
    uint256 reward = harvestsFt[msg.sender];
    if (reward > 0) {
      averse.transferFrom(POOL_WALLET, msg.sender, harvestsFt[msg.sender]);
      harvestsFt[msg.sender] = 0;
    }
  }

  function getTotalClaimableFt(address _user) external view returns(uint256) {
    uint256 time = block.timestamp;
    uint256 pending = stakeBalancesFt[_user] * tokenRewardRate * (time - lastUpdateFt[_user]) / 86400 / 10000;
    return harvestsFt[_user] + pending;
  }

  function setNftContractAddr(address nftAddr) external onlyOwner {
    arenaverseNFT = IArenaverseNFT(nftAddr);
  }

  function setFtContractAddr(address ftAddr) external onlyOwner {
    averse = IAVERSE(ftAddr);
  }

  function setNFTRewardRate(uint _rate) external onlyOwner {
    NFTRewardRate = _rate;
  }

  function setTokenRewardRate(uint256 _rate) external onlyOwner {
    tokenRewardRate = _rate;
  }

  function setLockPeriod(uint256 _period) external onlyOwner {
    LOCK_PERIOD = _period;
  }

  function setPOOLWALLET(address _address) external onlyOwner {
    POOL_WALLET = _address;
  }

  function canHarvest(address _owner) external view returns(bool) {
    if (lockTime[_owner] + LOCK_PERIOD <= block.timestamp)
      return true;
    return false;
  }
}