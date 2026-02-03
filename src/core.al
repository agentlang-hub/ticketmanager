module ticketmanager.core

record incidentInformation {
    sys_id String @optional,
    status String @optional,
    data Any @optional,
    category String @optional,
    ai_status String @optional,
    ai_processor String @optional,
    requires_human Boolean @optional,
    ai_reason String @optional,
    resolution String @optional
}

entity TicketMetrics {
    id UUID @id @default(uuid()),
    snapshotDate DateTime @default(now()) @indexed,
    totalTickets Int,
    ticketsInProcessing Int,
    ticketsProcessed Int,
    ticketsFailedToProcess Int,
    dnsWlanTotal Int,
    dnsWlanResolved Int,
    dnsWlanFailed Int,
    authTotal Int,
    authResolved Int,
    authFailed Int,
    accessTotal Int,
    accessResolved Int,
    accessFailed Int,
    networkTotal Int,
    networkResolved Int,
    networkFailed Int,
    otherTotal Int
}

entity ProcessorStats {
    id UUID @id @default(uuid()),
    processorName @enum("dnsprocessor", "authprocessor", "accessprocessor", "networkprocessor") @indexed,
    snapshotDate DateTime @default(now()),
    ticketsProcessed Int,
    ticketsFailed Int,
    avgResolutionTimeMs Int @optional,
    successRate Decimal
}

entity HumanInterventionLog {
    id UUID @id @default(uuid()),
    ticketId String @indexed,
    servicenowId String,
    category String,
    reason String,
    createdAt DateTime @default(now()),
    resolvedAt DateTime @optional,
    resolvedBy String @optional
}


agent ticketCategorizer {
    instruction "Categorize the ticket instance into DNS_WLAN, AUTH, ACCESS, NETWORK, OTHER.
Properly understand the ticket instance data and categorize it.
Only return one of the strings [DNS_WLAN, AUTH, ACCESS, NETWORK, OTHER] and nothing else."
}


flow ticketOrchestrator {
    ticketCategorizer --> "DNS_WLAN" {servicenow.incident {sys_id? incidentinformation.sys_id, ai_status "in-processing", ai_processor "dns_wlan", category "DNS_WLAN", requires_human false, ai_reason "Auto-triaged to DNS/WLAN processor.", data {"comments": "AI triage: routed to DNS/WLAN processor.\nKey context:\n- Summary: " + incidentinformation.data.short_description + "\n- Details: " + incidentinformation.data.description + "\nDNS info checklist:\n- Record name, type (A/CNAME/TXT), target/value, TTL\n- Environment/zone and owner\n- Change window/approval\nWLAN info checklist:\n- SSID, security mode, VLAN/subnet\n- Location/site and access scope\n- Device constraints or MAC filters\nResolution guidance: validate requested details, confirm ownership and scope, apply change, and verify resolution."}}}
    ticketCategorizer --> "AUTH" {servicenow.incident {sys_id? incidentinformation.sys_id, ai_status "in-processing", ai_processor "auth", category "AUTH", requires_human false, ai_reason "Auto-triaged to auth processor.", data {"comments": "AI triage: routed to auth processor.\nKey context:\n- Summary: " + incidentinformation.data.short_description + "\n- Details: " + incidentinformation.data.description + "\nAuth info checklist:\n- User email/ID and system\n- Error message and timestamp\n- Last successful login and MFA status\nResolution guidance: verify identity, identify issue type, apply reset/unlock, and confirm access restored."}}}
    ticketCategorizer --> "ACCESS" {servicenow.incident {sys_id? incidentinformation.sys_id, ai_status "in-processing", ai_processor "access", category "ACCESS", requires_human false, ai_reason "Auto-triaged to access processor.", data {"comments": "AI triage: routed to access processor.\nKey context:\n- Summary: " + incidentinformation.data.short_description + "\n- Details: " + incidentinformation.data.description + "\nAccess info checklist:\n- Resource/system and exact entitlement\n- Duration/temporary vs permanent\n- Business justification and approver\nResolution guidance: confirm scope, validate approvals, apply access change, and verify entitlement."}}}
    ticketCategorizer --> "NETWORK" {servicenow.incident {sys_id? incidentinformation.sys_id, ai_status "in-processing", ai_processor "network", category "NETWORK", requires_human false, ai_reason "Auto-triaged to network processor.", data {"comments": "AI triage: routed to network processor.\nKey context:\n- Summary: " + incidentinformation.data.short_description + "\n- Details: " + incidentinformation.data.description + "\nNetwork info checklist:\n- Location/site and affected service\n- Error symptoms and timestamps\n- Device/VPN client details or source/destination\nResolution guidance: isolate issue type, check connectivity, apply fix or route to network ops, and confirm service restored."}}}
    ticketCategorizer --> "OTHER" {servicenow.incident {sys_id? incidentinformation.sys_id, ai_status "failed-to-process", ai_processor "other", category "OTHER", resolution "Ticket category could not be determined.", requires_human true, ai_reason "Unable to classify incident category.", data {"comments": "REQUIRES MANUAL INTERVENTION: Unable to classify incident category.\nKey context:\n- Summary: " + incidentinformation.data.short_description + "\n- Details: " + incidentinformation.data.description + "\nSuggested next steps: identify category, gather missing details, and route to correct resolver."}}}
}

@public agent ticketOrchestrator {
    role "You are a ticket management orchestrator that routes incidents to specialized processors."
}

workflow @after create:servicenow/incident {

    {incidentInformation {
        sys_id servicenow/incident.sys_id,
        status servicenow/incident.status,
        data servicenow/incident.data,
        category servicenow/incident.category,
        ai_status servicenow/incident.ai_status,
        ai_processor servicenow/incident.ai_processor,
        requires_human servicenow/incident.requires_human,
        ai_reason servicenow/incident.ai_reason,
        resolution servicenow/incident.resolution
    }}

    {ticketOrchestrator {message servicenow/incident}}
}

@public workflow getDashboardStats {
    {
        servicenow/incident? {},
        @into {status servicenow/incident.ai_status, count @count(servicenow/incident.sys_id)},
        @groupBy(servicenow/incident.ai_status)
    }
}

@public workflow getStatsByCategory {
    {servicenow/incident {category? getStatsByCategory.category}}
}

@public workflow getProcessorPerformance {
    {ProcessorStats {processorName? getProcessorPerformance.processorName}}
}

@public workflow getHumanInterventionQueue {
    {servicenow/incident {requires_human? true}}
}

@public workflow refreshMetrics {
    {servicenow/incident? {}} @as allTickets;
    {servicenow/incident {ai_status? "in-processing"}} @as inProcessingTickets;
    {servicenow/incident {ai_status? "processed"}} @as processedTickets;
    {servicenow/incident {ai_status? "failed-to-process"}} @as failedTickets;

    {servicenow/incident {category? "DNS_WLAN"}} @as dnsTotal;
    {servicenow/incident {category? "DNS_WLAN", ai_status? "processed"}} @as dnsResolved;
    {servicenow/incident {category? "DNS_WLAN", ai_status? "failed-to-process"}} @as dnsFailed;

    {servicenow/incident {category? "AUTH"}} @as authTotal;
    {servicenow/incident {category? "AUTH", ai_status? "processed"}} @as authResolved;
    {servicenow/incident {category? "AUTH", ai_status? "failed-to-process"}} @as authFailed;

    {servicenow/incident {category? "ACCESS"}} @as accessTotal;
    {servicenow/incident {category? "ACCESS", ai_status? "processed"}} @as accessResolved;
    {servicenow/incident {category? "ACCESS", ai_status? "failed-to-process"}} @as accessFailed;

    {servicenow/incident {category? "NETWORK"}} @as networkTotal;
    {servicenow/incident {category? "NETWORK", ai_status? "processed"}} @as networkResolved;
    {servicenow/incident {category? "NETWORK", ai_status? "failed-to-process"}} @as networkFailed;

    {servicenow/incident {category? "OTHER"}} @as otherTotal;

    {TicketMetrics {
        totalTickets allTickets.length,
        ticketsInProcessing inProcessingTickets.length,
        ticketsProcessed processedTickets.length,
        ticketsFailedToProcess failedTickets.length,
        dnsWlanTotal dnsTotal.length,
        dnsWlanResolved dnsResolved.length,
        dnsWlanFailed dnsFailed.length,
        authTotal authTotal.length,
        authResolved authResolved.length,
        authFailed authFailed.length,
        accessTotal accessTotal.length,
        accessResolved accessResolved.length,
        accessFailed accessFailed.length,
        networkTotal networkTotal.length,
        networkResolved networkResolved.length,
        networkFailed networkFailed.length,
        otherTotal otherTotal.length
    }}
}
