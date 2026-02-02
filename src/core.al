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


agent ticketCategorizer {
    instruction "Categorize the ticket instance into DNS_WLAN, AUTH, ACCESS, NETWORK, OTHER.
Properly understand the ticket instance data and categorize it.
Only return one of the strings [DNS_WLAN, AUTH, ACCESS, NETWORK, OTHER] and nothing else."
}


flow ticketOrchestrator {
    ticketCategorizer --> "DNS_WLAN" {servicenow.incident {sys_id? incidentinformation.sys_id, ai_status "in-processing", ai_processor "dns_wlan", category "DNS_WLAN", requires_human false}}
    ticketCategorizer --> "AUTH" {servicenow.incident {sys_id? incidentinformation.sys_id, ai_status "in-processing", ai_processor "auth", category "AUTH", requires_human false}}
    ticketCategorizer --> "ACCESS" {servicenow.incident {sys_id? incidentinformation.sys_id, ai_status "in-processing", ai_processor "access", category "ACCESS", requires_human false}}
    ticketCategorizer --> "NETWORK" {servicenow.incident {sys_id? incidentinformation.sys_id, ai_status "in-processing", ai_processor "network", category "NETWORK", requires_human false}}
    ticketCategorizer --> "OTHER" {servicenow.incident {sys_id? incidentinformation.sys_id, ai_status "failed-to-process", ai_processor "other", category "OTHER", resolution "Ticket category could not be determined.", requires_human true}}
}

@public agent ticketOrchestrator {
    role "You are a ticket management orchestrator that routes incidents to specialized processors."
}

workflow @after create:servicenow/incident {

    {incidentInformation {
        sys_id servicenow/incident.sys_id,
        status servicenow/incident.state,
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
