;; AIModelDAO - Decentralized AI Model Governance
;; Allows token holders to vote on AI model parameters and funding

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PROPOSAL (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-VOTING-CLOSED (err u103))
(define-constant ERR-INSUFFICIENT-QUORUM (err u104))
(define-constant ERR-PROPOSAL-EXECUTED (err u105))
(define-constant ERR-INVALID-DELEGATE (err u106))
(define-constant ERR-TREASURY-INSUFFICIENT (err u107))
(define-constant ERR-MIN-STAKE-REQUIRED (err u108))
(define-constant ERR-INVALID-MODEL-PARAMS (err u109))
(define-constant ERR-COOLDOWN-ACTIVE (err u110))
(define-constant ERR-INVALID-REWARD (err u111))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u112))

(define-data-var proposal-count uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var min-proposal-stake uint u1000)
(define-data-var quorum-threshold uint u30)
(define-data-var voting-period uint u1440)
(define-data-var reward-pool uint u0)
(define-data-var total-staked uint u0)
(define-data-var governance-fee uint u10)

(define-map proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    votes-for: uint,
    votes-against: uint,
    end-block: uint,
    executed: bool,
    proposal-type: (string-ascii 30),
    funding-amount: uint,
    target-address: (optional principal),
    model-params: (string-ascii 200),
    priority: uint
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { voted: bool, vote-type: bool, voting-power: uint, timestamp: uint }
)

(define-map dao-tokens
  { holder: principal }
  { balance: uint, staked: uint, last-claim: uint, reputation: uint }
)

(define-map delegations
  { delegator: principal }
  { delegate: principal, voting-power: uint, expiry: uint }
)

(define-map proposal-stakes
  { proposal-id: uint }
  { stake-amount: uint, stake-returned: bool }
)

(define-map governance-settings
  { setting: (string-ascii 30) }
  { value: uint }
)

(define-map member-roles
  { member: principal }
  { role: (string-ascii 20), permissions: uint, reputation-bonus: uint }
)

(define-map model-configurations
  { config-id: uint }
  {
    name: (string-ascii 50),
    parameters: (string-ascii 300),
    performance-metrics: uint,
    active: bool,
    creator: principal
  }
)

(define-map voting-rewards
  { voter: principal, period: uint }
  { rewards-earned: uint, claimed: bool }
)

(define-public (initialize)
  (begin
    (map-set dao-tokens { holder: CONTRACT-OWNER } { balance: u1000000, staked: u0, last-claim: block-height, reputation: u100 })
    (map-set governance-settings { setting: "min-stake" } { value: u1000 })
    (map-set governance-settings { setting: "quorum" } { value: u30 })
    (map-set governance-settings { setting: "voting-period" } { value: u1440 })
    (map-set governance-settings { setting: "cooldown-period" } { value: u144 })
    (map-set member-roles { member: CONTRACT-OWNER } { role: "admin", permissions: u255, reputation-bonus: u50 })
    (var-set treasury-balance u500000)
    (var-set reward-pool u100000)
    (ok true)
  )
)

(define-public (mint-tokens (recipient principal) (amount uint))
  (let
    (
      (current-balance (get balance (get-token-balance recipient)))
      (sender-role (get role (get-member-role tx-sender)))
    )
    (asserts! (is-eq sender-role "admin") ERR-NOT-AUTHORIZED)
    (map-set dao-tokens 
      { holder: recipient }
      { 
        balance: (+ current-balance amount),
        staked: (get staked (get-token-balance recipient)),
        last-claim: block-height,
        reputation: (get reputation (get-token-balance recipient))
      })
    (ok amount)
  )
)

(define-public (transfer-tokens (recipient principal) (amount uint))
  (let
    (
      (sender-balance (get balance (get-token-balance tx-sender)))
    )
    (asserts! (>= sender-balance amount) ERR-NOT-AUTHORIZED)
    (map-set dao-tokens { holder: tx-sender }
      {
        balance: (- sender-balance amount),
        staked: (get staked (get-token-balance tx-sender)),
        last-claim: (get last-claim (get-token-balance tx-sender)),
        reputation: (get reputation (get-token-balance tx-sender))
      })
    (map-set dao-tokens { holder: recipient }
      {
        balance: (+ (get balance (get-token-balance recipient)) amount),
        staked: (get staked (get-token-balance recipient)),
        last-claim: (get last-claim (get-token-balance recipient)),
        reputation: (get reputation (get-token-balance recipient))
      })
    (ok amount)
  )
)

(define-public (stake-tokens (amount uint))
  (let
    (
      (current-balance (get balance (get-token-balance tx-sender)))
      (current-stake (get staked (get-token-balance tx-sender)))
    )
    (asserts! (>= current-balance amount) ERR-NOT-AUTHORIZED)
    (map-set dao-tokens 
      { holder: tx-sender }
      { 
        balance: (- current-balance amount),
        staked: (+ current-stake amount),
        last-claim: block-height,
        reputation: (get reputation (get-token-balance tx-sender))
      })
    (var-set total-staked (+ (var-get total-staked) amount))
    (ok true)
  )
)

(define-public (unstake-tokens (amount uint))
  (let
    (
      (current-stake (get staked (get-token-balance tx-sender)))
      (current-balance (get balance (get-token-balance tx-sender)))
      (last-claim (get last-claim (get-token-balance tx-sender)))
    )
    (asserts! (>= current-stake amount) ERR-NOT-AUTHORIZED)
    (asserts! (> (- block-height last-claim) u144) ERR-COOLDOWN-ACTIVE)
    (map-set dao-tokens 
      { holder: tx-sender }
      { 
        balance: (+ current-balance amount),
        staked: (- current-stake amount),
        last-claim: block-height,
        reputation: (get reputation (get-token-balance tx-sender))
      })
    (var-set total-staked (- (var-get total-staked) amount))
    (ok true)
  )
)
