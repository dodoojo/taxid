;; Insurance Contract - Fixed Version

;; Data storage
(define-data-var pool uint u0)
(define-map policies uint {holder: principal, premium: uint, payout: uint, active: bool})
(define-data-var next-policy-id uint u1)

;; Error constants
(define-constant ERR-POLICY-NOT-FOUND (err u1))
(define-constant ERR-INSUFFICIENT-FUNDS (err u2))
(define-constant ERR-POLICY-INACTIVE (err u3))
(define-constant ERR-INVALID-AMOUNT (err u4))
(define-constant ERR-INSUFFICIENT-POOL-FUNDS (err u5))
(define-constant ERR-ARITHMETIC-OVERFLOW (err u6))
(define-constant ERR-INVALID-POLICY-ID (err u7))

;; Constants for validation
(define-constant MAX-PAYOUT u1000000000000) ;; 1 million STX in microSTX
(define-constant MIN-PAYOUT u1000000) ;; 1 STX in microSTX
(define-constant MAX-POLICY-ID u4294967295) ;; Max uint value

;; Calculate premium as 10% of payout amount with overflow protection
(define-read-only (get-premium-for (payout uint))
  (begin
    ;; Validate payout is within acceptable range
    (asserts! (and (>= payout MIN-PAYOUT) (<= payout MAX-PAYOUT)) ERR-INVALID-AMOUNT)
    ;; Safe multiplication with overflow check
    (let ((temp-calc (* payout u10)))
      (asserts! (>= temp-calc payout) ERR-ARITHMETIC-OVERFLOW)
      (ok (/ temp-calc u100)))))

;; Buy insurance policy - Alternative approach with unwrap!
(define-public (buy-policy (payout uint))
  (let ((premium (unwrap! (get-premium-for payout) ERR-INVALID-AMOUNT))
        (policy-id (var-get next-policy-id)))
    (begin
      ;; Validate policy ID hasn't overflowed
      (asserts! (< policy-id MAX-POLICY-ID) ERR-ARITHMETIC-OVERFLOW)
      ;; Validate premium calculation
      (asserts! (> premium u0) ERR-INVALID-AMOUNT)
      ;; Transfer premium from buyer to contract
      (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
      ;; Create new policy
      (map-set policies policy-id {
        holder: tx-sender,
        premium: premium,
        payout: payout,
        active: true
      })
      ;; Safe pool update with overflow check
      (let ((new-pool (+ (var-get pool) premium)))
        (asserts! (>= new-pool (var-get pool)) ERR-ARITHMETIC-OVERFLOW)
        (var-set pool new-pool))
      ;; Safe policy ID increment
      (var-set next-policy-id (+ policy-id u1))
      (ok policy-id))))

;; Trigger insurance payout with comprehensive validation
(define-public (trigger-payout (policy-id uint))
  (begin
    ;; Validate policy ID is within reasonable bounds
    (asserts! (and (> policy-id u0) (< policy-id (var-get next-policy-id))) ERR-INVALID-POLICY-ID)
    
    (let ((policy-option (map-get? policies policy-id)))
      (match policy-option
        policy
          (if (get active policy)
            (let ((payout-amount (get payout policy))
                  (policy-holder (get holder policy))
                  (current-pool (var-get pool))
                  (contract-balance (stx-get-balance (as-contract tx-sender))))
              
              ;; Comprehensive validation before payout
              ;; 1. Validate payout amount is reasonable
              (asserts! (and (> payout-amount u0) (<= payout-amount MAX-PAYOUT)) ERR-INVALID-AMOUNT)
              
              ;; 2. Check if contract has sufficient STX balance
              (asserts! (>= contract-balance payout-amount) ERR-INSUFFICIENT-FUNDS)
              
              ;; 3. Check if pool accounting has sufficient funds
              (asserts! (>= current-pool payout-amount) ERR-INSUFFICIENT-POOL-FUNDS)
              
              ;; 4. Validate subtraction won't underflow
              (asserts! (>= current-pool payout-amount) ERR-ARITHMETIC-OVERFLOW)
              
              ;; Transfer payout to policy holder
              (try! (as-contract (stx-transfer? payout-amount tx-sender policy-holder)))
              
              ;; Deactivate the policy
              (map-set policies policy-id {
                holder: (get holder policy),
                premium: (get premium policy),
                payout: (get payout policy),
                active: false
              })
              
              ;; Safe pool balance update (already validated above)
              (var-set pool (- current-pool payout-amount))
              (ok true))
            ERR-POLICY-INACTIVE)
        ERR-POLICY-NOT-FOUND))))

;; Read-only functions for querying with input validation
(define-read-only (get-pool-balance)
  (var-get pool))

(define-read-only (get-policy (policy-id uint))
  (if (and (> policy-id u0) (< policy-id (var-get next-policy-id)))
    (map-get? policies policy-id)
    none))

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender)))

(define-read-only (get-next-policy-id)
  (var-get next-policy-id))

;; Additional helper functions for better validation
(define-read-only (is-valid-policy-id (policy-id uint))
  (and (> policy-id u0) (< policy-id (var-get next-policy-id))))

(define-read-only (get-policy-count)
  (- (var-get next-policy-id) u1))

;; Function to check if a policy exists and is active
(define-read-only (is-policy-active (policy-id uint))
  (match (get-policy policy-id)
    policy (get active policy)
    false))