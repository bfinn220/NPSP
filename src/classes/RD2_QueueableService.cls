/*
    Copyright (c) 2019 Salesforce.org
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Salesforce.org nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/
/**
* @author Salesforce.org
* @date 2019
* @group Recurring Donations
* @description Queueable Services for Enhanced Recurring Donations
*
*/
public class RD2_QueueableService {

    /**
     * @description Queues up Opp eval service to recalculate Next Donation Date,
     * Current/Next Year Value and re-evaluate Opportunities on the Recurring Donation.
     * @param rdId Recurring Donation Id
     * @return void
     */
    public static void enqueueOppEvalService(Id rdId, Boolean isScheduleChanged) { 
        Set<Id> rdIdsWhereScheduleChanged = new Set<Id>();
        if (isScheduleChanged) {
            rdIdsWhereScheduleChanged.add(rdId);
        }
        enqueueOppEvalService(new Set<Id>{ rdId }, rdIdsWhereScheduleChanged);
    }

    /**
     * @description Queues up Opp eval service to recalculate Next Donation Date,
     * Current/Next Year Value and re-evaluate Opportunities on specified Recurring Donations.
     * @param rdIds Recurring Donation Ids
     * @return void
     */
    public static void enqueueOppEvalService(Set<Id> rdIds) { 
        enqueueOppEvalService(rdIds, null);
    }

    /**
     * @description Queues up Opp eval service to recalculate Next Donation Date,
     * Current/Next Year Value and re-evaluate Opportunities on specified Recurring Donations.
     * @param rdIds Recurring Donation Ids
     * @param rdIdsWhereScheduleChanged - Ids of Recurring Donation for which a schedule has been changed
     * @return void
     */
    public static void enqueueOppEvalService(Set<Id> rdIds, Set<Id> rdIdsWhereScheduleChanged) { 
        EvaluateInstallmentOpportunities service = new EvaluateInstallmentOpportunities(rdIds, rdIdsWhereScheduleChanged);

        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(service);

        } else {
            service.executeOppEvaluationService();
        }
    }

    /**
     * @description Queueable service to process Installment Opportunities for a Recurring Donation
     * that was inserted or modified.
     */
    public class EvaluateInstallmentOpportunities implements Queueable {
        Set<Id> rdIds;

        /**
        * @description Contains Recurring Donation Ids for which schedule has been changed
        */
        @TestVisible
        private Set<Id> rdIdsWhereScheduleChanged {
            get {
                if (rdIdsWhereScheduleChanged == null) {
                    rdIdsWhereScheduleChanged = new Set<Id>();
                }
                return rdIdsWhereScheduleChanged;
            } set;
        }

        /***
         * @description Constructor
         * @param rdIds - the RD Ids to process in this Queueable action
         */
        public EvaluateInstallmentOpportunities(Set<Id> rdIds) {
            this.rdIds = rdIds;
        }

        /***
         * @description Constructor
         * @param rdIds - the RD Ids to process in this Queueable action
         * @param rdIdsWhereScheduleChanged - Ids of Recurring Donations that have a changed schedule
         */
        public EvaluateInstallmentOpportunities(Set<Id> rdIds, Set<Id> rdIdsWhereScheduleChanged) {
            this.rdIds = rdIds;
            this.rdIdsWhereScheduleChanged = rdIdsWhereScheduleChanged;
        }

        /**
         * @description Execute method called when the Queueable runs. Delegates to the
         * evaluation service
         * @param context queuableContext
         */
        public void execute(QueueableContext context) {
            if (rdIds == null || rdIds.isEmpty()) {
                return;
            }

            executeOppEvaluationService();
        }

        /**
         * @description Delegate processing of the Recurring Donations to the Evaluation Service
         */
        public void executeOppEvaluationService() {
            new RD2_OpportunityEvaluationService()
                .withRds(rdIds)
                .withScheduleChanged(rdIdsWhereScheduleChanged)
                .evaluateOpportunities();
        }
    }

    /**
     * @description Queueable service to process inserted Recurring Donations that have a value
     * in the Elevate CommitmentId__c field.
     */
    public class ElevateOpportunityMatcher implements Queueable {
        Map<String, Id> rdIdByCommitmentId;

        /***
         * @description Constructor
         * @param rdIdByCommitmentId - Map of CommitmentId's to RecurringDonation.Id
         */
        public ElevateOpportunityMatcher(Map<String, Id> rdIdByCommitmentId) {
            this.rdIdByCommitmentId = rdIdByCommitmentId;
        }

        /**
         * @description Execute method called when the Queueable runs. Delegates to the
         * evaluation service
         * @param context queuableContext
         */
        public void execute(QueueableContext context) {
            if (rdIdByCommitmentId == null || rdIdByCommitmentId.isEmpty()) {
                return;
            }

            match();
        }

        /**
         * @description Delegate processing of the Recurring Donations to the Evaluation Service
         */
        public void match() {
            new RD2_ElevateIntegrationService()
                .matchRecurringDonationsToOpps(rdIdByCommitmentId);
        }
    }

    /**
     * @description Queueable service to make callouts to Elevate payment services and cancel commitments 
     */
    public class CancelCommitmentService implements Queueable, Database.AllowsCallouts {
        List<npe03__Recurring_Donation__c> closedRDs;

        /**
        * @description Constructor
        * @param closedRDs Closed Recurring Donations containing Commitment Id
        */
        public CancelCommitmentService(List<npe03__Recurring_Donation__c> closedRDs) {
            this.closedRDs = closedRDs;
        }

        /**
         * @description Cancel Commitments in Elevate payment services
         * @param context queuableContext
         */
        public void execute(QueueableContext context) {
            if (closedRDs == null || closedRDs.isEmpty()) {
                return;
            }

            new RD2_ElevateIntegrationService()
                .cancelCommitments(closedRDs);
        }
    }
}