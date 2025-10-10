;; Insurance Contract - Enhanced with Claim Validation System

;; Data storage
(define-data-var pool uint u0)
(define-map policies uint {holder: principal, premium: uint, payout: uint, active: bool, created-at: uint})
(define-data-var next-policy-id uint u1)

;; Claim validation system
(define-map claims uint {
  policy-id: uint,
  claimant: principal,
  submitted-at: uint,
  evidence-hash: (buff 32),
  status: (string-ascii 20),
  votes-for: uint,
  votes-against: uint,
  voting-deadline: uint
})
(define-data-var next-claim-id uint u1)

;; Governance system
(define-map validators principal {active: bool, stake: uint, reputation: uint})
(define-data-var min-validator-stake uint u10000000) ;; 10 STX minimum stake
(define-data-var claim-voting-period uint u144) ;; ~24 hours in blocks
(define-data-var min-votes-required uint u3)

;; Error constants
(define-constant ERR-POLICY-NOT-FOUND (err u1))
(define-constant ERR-INSUFFICIENT-FUNDS (err u2))
(define-constant ERR-POLICY-INACTIVE (err u3))
(define-constant ERR-INVALID-AMOUNT (err u4))
(define-constant ERR-INSUFFICIENT-POOL-FUNDS (err u5))
(define-constant ERR-ARITHMETIC-OVERFLOW (err u6))
(define-constant ERR-INVALID-POLICY-ID (err u7))
(define-constant ERR-UNAUTHORIZED (err u8))
(define-constant ERR-CLAIM-NOT-FOUND (err u9))
(define-constant ERR-CLAIM-ALREADY-EXISTS (err u10))
(define-constant ERR-VOTING-PERIOD-ENDED (err u11))
(define-constant ERR-VOTING-PERIOD-ACTIVE (err u12))
(define-constant ERR-INSUFFICIENT-VOTES (err u13))
(define-constant ERR-NOT-VALIDATOR (err u14))
(define-constant ERR-ALREADY-VOTED (err u15))

;; Constants for validation
(define-constant MAX-PAYOUT u1000000000000) ;; 1 million STX in microSTX
(define-constant MIN-PAYOUT u1000000) ;; 1 STX in microSTX
(define-constant MAX-POLICY-ID u4294967295) ;; Max uint value

;; Validator registration
(define-public (register-validator (stake uint))
  (begin
    (asserts! (>= stake (var-get min-validator-stake)) ERR-INSUFFICIENT-FUNDS)
    (try! (stx-transfer? stake tx-sender (as-contract tx-sender)))
    (map-set validators tx-sender {
      active: true,
      stake: stake,
      reputation: u100
    })
    (ok true)))

;; Calculate premium as 10% of payout amount with overflow protection
(define-read-only (get-premium-for (payout uint))
  (begin
    (asserts! (and (>= payout MIN-PAYOUT) (<= payout MAX-PAYOUT)) ERR-INVALID-AMOUNT)
    (let ((temp-calc (* payout u10)))
      (asserts! (>= temp-calc payout) ERR-ARITHMETIC-OVERFLOW)
      (ok (/ temp-calc u100)))))

;; Buy insurance policy - Enhanced with timestamp
(define-public (buy-policy (payout uint))
  (let ((premium (unwrap! (get-premium-for payout) ERR-INVALID-AMOUNT))
        (policy-id (var-get next-policy-id)))
    (begin
      (asserts! (< policy-id MAX-POLICY-ID) ERR-ARITHMETIC-OVERFLOW)
      (asserts! (> premium u0) ERR-INVALID-AMOUNT)
      (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
      (map-set policies policy-id {
        holder: tx-sender,
        premium: premium,
        payout: payout,
        active: true,
        created-at: stacks-block-height
      })
      (let ((new-pool (+ (var-get pool) premium)))
        (asserts! (>= new-pool (var-get pool)) ERR-ARITHMETIC-OVERFLOW)
        (var-set pool new-pool))
      (var-set next-policy-id (+ policy-id u1))
      (ok policy-id))))

;; Submit claim for validation
(define-public (submit-claim (policy-id uint) (evidence-hash (buff 32)))
  (begin
    (asserts! (and (> policy-id u0) (< policy-id (var-get next-policy-id))) ERR-INVALID-POLICY-ID)
    
    (let ((policy-option (map-get? policies policy-id)))
      (match policy-option
        policy
          (begin
            ;; Only policy holder can submit claims
            (asserts! (is-eq tx-sender (get holder policy)) ERR-UNAUTHORIZED)
            (asserts! (get active policy) ERR-POLICY-INACTIVE)
            
            ;; Check if claim already exists for this policy
            (asserts! (is-none (get-active-claim-for-policy policy-id)) ERR-CLAIM-ALREADY-EXISTS)
            
            (let ((claim-id (var-get next-claim-id))
                  (voting-deadline (+ stacks-block-height (var-get claim-voting-period))))
              
              (map-set claims claim-id {
                policy-id: policy-id,
                claimant: tx-sender,
                submitted-at: stacks-block-height,
                evidence-hash: evidence-hash,
                status: "pending",
                votes-for: u0,
                votes-against: u0,
                voting-deadline: voting-deadline
              })
              
              (var-set next-claim-id (+ claim-id u1))
              (ok claim-id)))
        ERR-POLICY-NOT-FOUND))))

;; Vote on claim (validators only)
(define-public (vote-on-claim (claim-id uint) (approve bool))
  (begin
    (let ((validator-info (unwrap! (map-get? validators tx-sender) ERR-NOT-VALIDATOR))
          (claim-info (unwrap! (map-get? claims claim-id) ERR-CLAIM-NOT-FOUND)))
      
      (asserts! (get active validator-info) ERR-NOT-VALIDATOR)
      (asserts! (< stacks-block-height (get voting-deadline claim-info)) ERR-VOTING-PERIOD-ENDED)
      (asserts! (is-eq (get status claim-info) "pending") ERR-VOTING-PERIOD-ENDED)
      
      ;; Update vote counts
      (let ((new-votes-for (if approve (+ (get votes-for claim-info) u1) (get votes-for claim-info)))
            (new-votes-against (if approve (get votes-against claim-info) (+ (get votes-against claim-info) u1))))
        
        (map-set claims claim-id (merge claim-info {
          votes-for: new-votes-for,
          votes-against: new-votes-against
        }))
        (ok true)))))

;; Process claim after voting period
(define-public (process-claim (claim-id uint))
  (let ((claim-info (unwrap! (map-get? claims claim-id) ERR-CLAIM-NOT-FOUND)))
    (begin
      (asserts! (>= stacks-block-height (get voting-deadline claim-info)) ERR-VOTING-PERIOD-ACTIVE)
      (asserts! (is-eq (get status claim-info) "pending") ERR-VOTING-PERIOD-ENDED)
      
      (let ((total-votes (+ (get votes-for claim-info) (get votes-against claim-info)))
            (votes-for (get votes-for claim-info))
            (policy-id (get policy-id claim-info)))
        
        (asserts! (>= total-votes (var-get min-votes-required)) ERR-INSUFFICIENT-VOTES)
        
        (if (> votes-for (/ total-votes u2))
          ;; Claim approved - trigger payout
          (begin
            (try! (execute-payout policy-id))
            (map-set claims claim-id (merge claim-info {status: "approved"}))
            (ok true))
          ;; Claim rejected
          (begin
            (map-set claims claim-id (merge claim-info {status: "rejected"}))
            (ok false)))))))

;; Internal payout execution (only called after claim validation)
(define-private (execute-payout (policy-id uint))
  (let ((policy-option (map-get? policies policy-id)))
    (match policy-option
      policy
        (if (get active policy)
          (let ((payout-amount (get payout policy))
                (policy-holder (get holder policy))
                (current-pool (var-get pool)))
            
            (asserts! (>= current-pool payout-amount) ERR-INSUFFICIENT-POOL-FUNDS)
            (try! (as-contract (stx-transfer? payout-amount tx-sender policy-holder)))
            
            (map-set policies policy-id (merge policy {active: false}))
            (var-set pool (- current-pool payout-amount))
            (ok true))
          ERR-POLICY-INACTIVE)
      ERR-POLICY-NOT-FOUND)))

;; Helper function to check for active claims
(define-read-only (get-active-claim-for-policy (policy-id uint))
  (let ((current-claim-id u1))
    ;; This is simplified - in practice, you'd need to iterate through claims
    ;; or maintain a separate mapping for policy-id -> claim-id
    none))

;; Read-only functions
(define-read-only (get-pool-balance)
  (var-get pool))

(define-read-only (get-policy (policy-id uint))
  (if (and (> policy-id u0) (< policy-id (var-get next-policy-id)))
    (map-get? policies policy-id)
    none))

(define-read-only (get-claim (claim-id uint))
  (map-get? claims claim-id))

(define-read-only (get-validator (validator principal))
  (map-get? validators validator))

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender)))
