// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.10;
pragma experimental ABIEncoderV2;

contract Token {

    /// returns total amount of tokens
    function totalSupply() public virtual view returns (uint256 supply) {}

    /// @param _owner The address from which the balance will be retrieved
    /// returns The balance
    function balanceOf(address _owner) public virtual view returns (uint256 balance) {}

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// returns Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) public virtual returns (bool success) {}

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// returns Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) public virtual returns (bool success) {}

    /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of wei to be approved for transfer
    /// returns Whether the approval was successful or not
    function approve(address _spender, uint256 _value) public virtual returns (bool success) {}

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// returns Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) public virtual view returns (uint256 remaining) {}

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

}



contract StandardToken is Token {

    mapping (address => uint256) balances;                          // token balances per user

    mapping (address => mapping (address => uint256)) allowed;      // ERC20 complience mostly
                                                                    // amount of tokens user allowed to spend from his balance
                                                                    // to another user

    function transfer(address _to, uint256 _value) public override returns (bool success) {
        //Default assumes totalSupply can't be over max (2^256 - 1).
        //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
        //Replace the if with this one instead.
        //if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
        if (balances[msg.sender] >= _value && _value > 0) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            emit Transfer(msg.sender, _to, _value);
            return true;
        } else { return false; }
    }

    function transferFrom(address _from, address _to, uint256 _value) public override returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            emit Transfer(_from, _to, _value);
            return true;
        } else { return false; }
    }

    function balanceOf(address _owner) public override view returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) public override returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public override view returns (uint256 remaining) {
      return allowed[_owner][_spender];
    }

    // Returns true if strings are equal (unsafe!)
    function compareStrings (string memory a, string memory b) public pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))) );
    }
}


contract RewardToken is StandardToken {

    uint8 constant FLAG_ABUSE = 4;

    // Challenge status is a enum
    enum ChallengeStatus {
        INVALID,        // Status by default is invalid
        NEW,            // An initial status for created challenge
        CONFIRMED,      // Challenge has been confirmed by bot as in progress
        FINISHED,       // Challenge has been finished by bot
        ERROR,          // Challenge resulted into an error and is cancelled
        TIMEOUT         // challenge request timed out
                        // (some challenges will never update under certain circumstances,
                        // so the TIMEOUT the challenge status CONFIRMED is unreliable
                        // without timeout check to detetct if it needs to be set to TIMEOUT
    }

    // Challenge is a request from user to time-limited service provided by bots
    // When bot confirms or finishes challenge, user score is reported
    // which is used to calculate reward in tokens that is immediatelly "transferred from the
    // bank to user's balance"
    struct Challenge {
        uint256 id;                                     // unique identifier of the challenge (ordinal)
        address user;                                   // request initiator
        uint256 createdAt;                              // timestamp of the request (uts)

        string group;                                   // challenge payload component
        uint32 resource;                                // challenge payload component

        ChallengeData data;                             // Challenge progress data

        uint8 flags;                                    // Extra state bit flags (like FLAG_ABUSE)
        uint256 userEtherCost;                          // aggregated gas price user (creator of challenge) have spent.
                                                        // May be compensated under circumstances on the next payout to user
    }

    // struct with dynamic data of the challenge
    struct ChallengeData {
        uint256 confirmedAt;                            // timestamp
        uint256 finishedAt;                             // timestamp

        ChallengeStatus status;                         // current status
        uint256 pointsBefore;                           // score of the user before
        uint256 pointsAfter;                            // and at the end of the challenge
        string error;                                   // in case of an error, hold description
        uint256 reward;                                 // amount of tokens assigned to sender as a result of the challenge

        uint256 serviceCost;                            // aggregated gas price bots (serving the contract) have spent managing the challenge
                                                        // if serviceCostsEnabled, witheld as a commission from the user on payouts
    }

    address public ceo;                                 // contract owner, has special abillities:
                                                        // modify array of authorized bots
                                                        // directly reward users from bank funds
                                                        // update rules array

    mapping (address => bool) public bots;              // authorized bots which will respond to challenge requests and update their status/data

    mapping (address => uint256) public donations;      // amount of ether sent by every user.
                                                        // this aggregated sum is only for informational purposes
                                                        // and does not include ether send as part of token purchases
                                                        // CEO investments (to bank) are also not included

    mapping (uint256 => Challenge) public challenges;   // Maps challenge ID to its data

    mapping (address => uint256) public userChallenge;  // Maps user address to his active challenge
                                                        // a user cannot have more than one ongoing challenge

    uint256 public numChallenges;                       // total number of created challenges
                                                        // ID of next challenge

    uint256 public totalOwnedTokens;                    // total number of tokens which have owners (not bank)

    uint256 public minBankForChallenge;                 // minimal amount of bank needed to start new challenges, as set by CEO
                                                        // Used as safety check to deny challenges if contract is low on funds

    uint256 public duration;                            // duration of a challenge, as set by the CEO

    uint256[] public rules;                             // rewarding rules, as set by CEO
                                                        // a sequence of [ threshold, rewardForPoint ] pairs used to calculate bonus;
                                                        // the array MUST be sorted from higher to lower point threshold values

    uint public numberOfRules;                          // number of effective rules (pairs in rules array)
                                                        // TODO: Why we don't use rules.length? Can this be removed?

    uint256 public weiPerToken;                         // how much ether we give or take for token, as set by CEO.
                                                        // Because weiPerToken can be changed and is not guaranteed, this will directly modify totalSupply
                                                        // and user balances in ether equivalent

    uint256 public requestTimeout;                      // maximum time before challenge is failed without confirmation or after confirmation+duration,
                                                        // as set by CEO

    mapping (address => uint256) public serviceCost;    // for every user, keep storing aggregated amount of service costs
                                                        // to be witheld in the next Sell() transaction
                                                        // Similar to Challenge.ServiceCost,
                                                        // only includes assigned (confirmed) commission amount pending rating on payout transfer.
                                                        // Do not include serviceCosts of challenges failed processing (if no abuse)

    bool public serviceCostsEnabled;                    // determines whether users will be charged for gas costs of service bots, as set by CEO

    mapping (address => uint256) public compensations;  // for every user, keep storing aggregated amount
                                                        // of gas price they spent on their transactions,
                                                        // specifically the part of which to be refunded to them
                                                        // on the next sell() as compensation for service outage.
                                                        // Similar to ChallengeData.UserEtherCost,
                                                        // only includes assigned (confirmed) compensation amount pending payout inclusion.
                                                        // Do not include userEtherCost to compensation before challenge is over
                                                        // (or if abuse flag is set when finished)

    /* Public variables of the token */

    // ERC20 complience mostly

    /*
    NOTE:
    The following variables are OPTIONAL vanities. One does not have to include them.
    They allow one to customise the token contract & in no way influences the core functionality.
    Some wallets/interfaces might not even bother to look at this information.
    */
    string public name;                   //fancy name: eg Simon Bucks
    uint8 public decimals;                //How many decimals to show. ie. There could 1000 base units with 3 decimals. Meaning 0.980 SBX = 980 base units. It's like comparing 1 wei to 1 ether.
    string public symbol;                 //An identifier: eg SBX
    string public version = 'H1.0';       //human 0.1 standard. Just an arbitrary versioning scheme.

    //
    // CHANGE THESE VALUES FOR YOUR TOKEN
    //

    // New challenge is created
    event ChallengeRequest(uint256 indexed _id, address indexed _user, string _group);

    // Challenge status was updated
    event ChallengeUpdate(uint256 indexed _id, ChallengeStatus indexed _status, uint256 _reward);

    //make sure this function name matches the contract name above. So if you're token is called TutorialToken, make sure the //contract name above is also TutorialToken instead of ERC20Token

    constructor(uint256 _weiPerToken, uint256 _minBankForChallenge, uint256 _rewardForPoint, uint256 _duration, uint256 _requestTimeout, bool _serviceCostsEnabled)
        public payable
    {
        ceo = msg.sender;                       // hire CEO

        weiPerToken = _weiPerToken;
        minBankForChallenge = _minBankForChallenge;
        duration = _duration;
        requestTimeout = _requestTimeout;
        serviceCostsEnabled = _serviceCostsEnabled;

        // Iniital rule
        rules.push(0);
        rules.push(_rewardForPoint);
        numberOfRules = 1;

        name = "Reward Token";                  // Set the name for display purposes
        decimals = 2;                           // Amount of decimals for display purposes
        symbol = "RWRD";                        // Set the symbol for display purposes

        rememberDonation();
    }

    /// returns total amount of tokens (directly tied to the contract balance)
    function totalSupply() public override view returns (uint256 supply) {
        return address(this).balance / weiPerToken;
    }

    /// returns total amount of tokens which are supported by ether, but do not have any owner (thus usable for new rewards)
    function totalBank() public view returns (uint256 bank) {
        uint256 all = totalSupply();
        if (all <= totalOwnedTokens) {
            return 0;
        }
        return all - totalOwnedTokens;
    }

    // Returns the threshold and reward for specific rule by non-array index (by rule number)
    function getRule(uint256 _ruleNumber) public view returns (uint256 threshold, uint256 rewardForPoint) {
        uint256 i = _ruleNumber * 2;
        return (rules[i], rules[i + 1]);
    }

    // if ether is sent to this address, accept it - increases totalSupply, remembering user donation
    fallback() external payable {
        rememberDonation();
    }
    receive() external payable {
        rememberDonation();
    }

    // Restricts function to only work if sender is service bot, authorized by CEO to
    // provide data and updates for challenge data
    modifier onlyForBots()
    {
        require(
            bots[msg.sender],
            "Sender not authorized (must be bot)."
        );
        // Do not forget the "_;"! It will
        // be replaced by the actual function
        // body when the modifier is used.
        _;
    }

    // Restricts function to only work if sender is contract CEO
    modifier onlyForCEO()
    {
        require(
            msg.sender == ceo,
            "Sender not authorized (must be CEO)."
        );
        // Do not forget the "_;"! It will
        // be replaced by the actual function
        // body when the modifier is used.
        _;
    }

    // Restricts function to only work if provided challenge has an active status
    modifier onlyForActiveChallenge(uint256 _id)
    {
        assert(_id < numChallenges);
        require(
            challenges[_id].data.status == ChallengeStatus.NEW || challenges[_id].data.status == ChallengeStatus.CONFIRMED,
            "Invalid challenge status (must be NEW or CONFIRMED)"
        );
        // Do not forget the "_;"! It will
        // be replaced by the actual function
        // body when the modifier is used.
        _;
    }

    // Restricts function to only work if provided challenge has status NEW (unconfirmed)
    modifier onlyForNewChallenge(uint256 _id)
    {
        require(
            challenges[_id].data.status == ChallengeStatus.NEW,
            "Invalid challenge status (must be NEW)"
        );
        // Do not forget the "_;"! It will
        // be replaced by the actual function
        // body when the modifier is used.
        _;
    }

    // Restricts function to only work if provided challenge has status CONFIRMED
    // and can finished at the current time
    modifier onlyForFinishingChallenge(uint256 _id)
    {
        require(
            challenges[_id].data.status == ChallengeStatus.CONFIRMED,
            "Invalid challenge status (must be CONFIRMED)"
        );

        require(
            challenges[_id].data.confirmedAt + duration <= now,
            "The challenge cannot be finished yet (check duration)"
        );

        // Do not forget the "_;"! It will
        // be replaced by the actual function
        // body when the modifier is used.
        _;
    }

    function newChallenge(string calldata group, uint32 resource, uint8 flags)
        public payable
    {
        uint256 startGas = gasleft();

        if (totalBank() < minBankForChallenge) {
            revert("Low on supply for new challenge (safety check)");
        }
        if (hasActiveChallenge(msg.sender)) {
            revert("You already have an ongoing challenge request");
        }
        if (bytes(group).length == 0 || resource <= 0) {
            revert("Invalid challenge request");
        }

        uint256 id = numChallenges;
        numChallenges++;

        challenges[id] = Challenge({
            id: id,
            user: msg.sender,
            createdAt: now,
            flags: flags,
            group: group,
            resource: resource,
            data: ChallengeData({
                confirmedAt: 0,
                finishedAt: 0,
                status: ChallengeStatus.NEW,
                pointsBefore: 0,
                pointsAfter: 0,
                error: "",
                reward: 0,
                serviceCost: 0
            }),
            userEtherCost: 0
        });

        userChallenge[msg.sender] = id;
        emit ChallengeRequest(id, msg.sender, group);

        rememberDonation();
        addUserCostsChallenge(id, startGas);
    }

    // Sell converts user token(s) to ether and sends ether to user
    // This will decreatse both totalBank() and totalSupply()
    // It will subtract the amount of commission for service (gas price from our side)
    // It will add the amount of compensations
    // If user has an ongoing challenge, it will be checked for timeout
    // (timeout compensations will be included into transfer of the function)
    // Allowed amounts are 0 and higher.
    function sell(uint256 requestTokens) public {
        if (requestTokens > balances[msg.sender]) {
            revert("You do not have enough tokens on your balance");
        }

        int256 requestEther = int256(requestTokens * weiPerToken);

        if (hasActiveChallenge(msg.sender)) {
            failChallengeIfTimeout(userChallenge[msg.sender]);
        }

        if(serviceCostsEnabled) {
            requestEther -= int256(serviceCost[msg.sender]);
        }
        serviceCost[msg.sender] = 0;

        // Only add compensations when possible
        int256 compensationIncluded = int256(compensations[msg.sender]);
        int256 maxEther = int256(address(this).balance);
        if(requestEther + compensationIncluded <= maxEther) {
            requestEther += compensationIncluded;
            compensations[msg.sender] = 0;
        }

        if (requestEther < 0) {
            revert("The balance is too low to add the service costs as commission (compensations excluded)");
        }

        // TODO: This needs more review
        assert(totalOwnedTokens >= requestTokens);

        balances[msg.sender] -= requestTokens;
        totalOwnedTokens -= requestTokens;

        msg.sender.transfer(uint256(requestEther));
        emit Transfer(msg.sender, address(this), requestTokens);
    }

    // Any user can buy theirself tokens in exchange to ether
    function buy() public payable {
        uint256 tokens = msg.value / weiPerToken;

        balances[msg.sender] += tokens;
        totalOwnedTokens += tokens;

        emit Transfer(address(this), msg.sender, tokens);
    }

    // Calculates reward according to the rules set by CEO
    function rewardForPoints(uint256 points)
        public view returns (uint256)
    {
        uint256 result = 0;

        for (uint i = 0; i < rules.length; i += 2) {
            if (points > rules[i]) {
                uint256 pointsAbove = (points - rules[i]);
                result += pointsAbove * rules[i+1];
                points -= pointsAbove;
            }
        }

        return result + points;
    }

    // BOT ONLY: Marks challenge failed with a message.
    // abuse: set to true to mark actions of a user as suspicious or willingfuly incorrect
    // on this challenge (they won't get gas compensation)
    function botFailChallenge(uint256 _id, string calldata error, bool abuse)
        public payable onlyForBots() onlyForActiveChallenge(_id)
    {
        uint256 startGas = gasleft();

        challenges[_id].data.status = ChallengeStatus.ERROR;
        challenges[_id].data.error = error;
        challenges[_id].data.finishedAt = now;

        address user = challenges[_id].user;
        userChallenge[user] = 0;

        if (!abuse) {
            compensations[user] += challenges[_id].userEtherCost;
        } else {
            challenges[_id].flags |= FLAG_ABUSE;
        }

        emit ChallengeUpdate(_id, ChallengeStatus.ERROR, 0);

        rememberDonation();
        addServiceCostsChallenge(_id, startGas);
    }

    // BOT ONLY: Marks challenge as started (confirmed)
    function botConfirmChallenge(uint256 _id, uint256 pointsBefore)
        public payable onlyForBots() onlyForNewChallenge(_id)
    {
        uint256 startGas = gasleft();

        if(!failChallengeIfTimeout(_id)) {

            challenges[_id].data.status = ChallengeStatus.CONFIRMED;
            challenges[_id].data.pointsBefore = pointsBefore;
            challenges[_id].data.confirmedAt = now;

            emit ChallengeUpdate(_id, ChallengeStatus.CONFIRMED, 0);
        }

        rememberDonation();
        addServiceCostsChallenge(_id, startGas);
    }

    // BOT ONLY: Marks challenge as finished (done) and triggers reward for user
    function botFinishChallenge(uint256 _id, uint256 pointsAfter)
        public payable onlyForBots() onlyForFinishingChallenge(_id)
    {
        uint256 startGas = gasleft();

        if(!failChallengeIfTimeout(_id)) {

            challenges[_id].data.status = ChallengeStatus.FINISHED;
            challenges[_id].data.pointsAfter = pointsAfter;
            challenges[_id].data.finishedAt = now;

            uint256 points = challenges[_id].data.pointsAfter - challenges[_id].data.pointsBefore;
            if(points < 0) {
                challenges[_id].data.error = "Provided data is incorrect. PointsBefore was higher than the PointsAfter sent with botFinishChallenge";
                challenges[_id].data.status = ChallengeStatus.ERROR;
                emit ChallengeUpdate(_id, ChallengeStatus.ERROR, 0);
            } else {
                uint256 tokenAmount = rewardForPoints(points);

                challenges[_id].data.reward = tokenAmount;

                address user = challenges[_id].user;
                balances[user] += tokenAmount;
                totalOwnedTokens += tokenAmount;

                userChallenge[user] = 0;

                emit ChallengeUpdate(_id, ChallengeStatus.FINISHED, tokenAmount);
                emit Transfer(address(this), user, tokenAmount);
            }
        }

        rememberDonation();
        addServiceCostsChallenge(_id, startGas);
    }

    // CEO ONLY: set restrictions and rewards
    function ceoUpdate(uint256 _minBankForChallenge, uint256 _duration, uint256 _weiPerToken, uint256 _requestTimeout, bool _serviceCostsEnabled)
        public payable onlyForCEO()
    {
        minBankForChallenge = _minBankForChallenge;
        duration = _duration;
        weiPerToken = _weiPerToken;
        requestTimeout = _requestTimeout;
        serviceCostsEnabled = _serviceCostsEnabled;

        rememberDonation();
    }

    // CEO ONLY: Updates the rules of reward system
    function ceoUpdateRules(uint256[] calldata _rules)
        public payable onlyForCEO()
    {
        rules = _rules;
        numberOfRules = _rules.length / 2;

        rememberDonation();
    }

    // CEO ONLY: remove or add authorization of bots
    function ceoAuthBots(bool auth, address[] calldata _bots)
        public payable onlyForCEO()
    {
        for (uint i = 0; i < _bots.length; i++) {
            bots[_bots[i]] = auth;
        }

        rememberDonation();
    }

    // CEO ONLY: moves tokens to user's balance
    function ceoRewardFromBank(address user, uint256 amountTokens)
        public payable onlyForCEO()
    {
        balances[user] += amountTokens;
        totalOwnedTokens += amountTokens;

        if (totalOwnedTokens > totalSupply()) {
            revert("Not enough bank for provided amount");
        }

        emit Transfer(address(this), user, amountTokens);

        rememberDonation();
    }

    // Checks whether user has an ongoing challenge request at the moment
    function hasActiveChallenge(address user) public view returns (bool) {
        uint256 _id = userChallenge[user];
        return challenges[_id].user == user && (
            challenges[_id].data.status == ChallengeStatus.NEW ||
            challenges[_id].data.status == ChallengeStatus.CONFIRMED
        );
    }

    // Mark challenge as timed out and emits event
    function onChallengeTimeout(uint256 _id)
        private onlyForActiveChallenge(_id)
    {
        challenges[_id].data.status = ChallengeStatus.TIMEOUT;

        address user = challenges[_id].user;

        userChallenge[user] = 0;

        compensations[user] += challenges[_id].userEtherCost;

        challenges[_id].data.finishedAt = now;

        emit ChallengeUpdate(_id, ChallengeStatus.TIMEOUT, 0);
    }

    // Checks if challenge has timed out and fails it if so. Returns true if challenge has timed out
    function failChallengeIfTimeout(uint256 _id)
        private returns (bool)
    {
        if (challenges[_id].data.status == ChallengeStatus.NEW) {
            if (now >= (challenges[_id].createdAt + requestTimeout)) {
                onChallengeTimeout(_id);
                return false;
            }
        }

        if (challenges[_id].data.status == ChallengeStatus.CONFIRMED) {
            if (now >= (challenges[_id].data.confirmedAt + duration + requestTimeout)) {
                onChallengeTimeout(_id);
                return true;
            }
        }

        return false;
    }

    // Saves the cost of current transaction as future commission in the payout to creator of the challenge
    function addServiceCostsChallenge(uint256 _id, uint256 startGas)
        private onlyForBots()
    {
        uint256 gasUsed = startGas - gasleft();
        uint256 commission = (gasUsed + 21000) * tx.gasprice + msg.value;

        challenges[_id].data.serviceCost += commission;

        address user = challenges[_id].user;

        if(serviceCostsEnabled) {
            serviceCost[user] += commission;
        } else {
            serviceCost[user] = 0;
        }
    }

    // Saves the cost of current transaction as future compensations in the payout to challenge creator
    // (userEtherCost applied only in case of challenge failure)
    // TODO: tx.gasprice must be limited for our budget safety to some reasonable value
    function addUserCostsChallenge(uint256 _id, uint256 startGas)
        private onlyForActiveChallenge(_id)
    {
        uint256 gasUsed = startGas - gasleft();
        uint256 txCosts = (gasUsed + 21000) * tx.gasprice + msg.value;

        challenges[_id].userEtherCost += txCosts;
    }

    // Saves value of current transaction to record of donations by the sender.
    // If sender is an authorized bot, donations are assigned to CEO's record
    function rememberDonation() private {
        if(bots[msg.sender]) {
            donations[ceo] += msg.value;
        } else {
            donations[msg.sender] += msg.value;
        }
    }
}
