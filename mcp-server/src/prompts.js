/**
 * Pre-execution prompt definitions for OSTEON context governance.
 */
export const PROMPTS = {
  bone_pre_execution_gate: {
    name: 'bone_pre_execution_gate',
    description: 'System prompt preparing an autonomous agent to operate strictly within BONE Context Governance invariants.',
    arguments: [
      {
        name: 'task_description',
        description: 'Detailed description of the upcoming coding or architectural task.',
        required: true
      }
    ],
    generate: (args) => {
      const task = args.task_description || 'General engineering task';
      return [
        {
          role: 'user',
          content: {
            type: 'text',
            text: `[OSTEON BONE PRE-EXECUTION GATE ACTIVE]

You are operating within an OSTEON BONE-governed software repository. Before proposing or writing any code, you MUST adhere to the following non-negotiable invariants:

1. **Pre-Flight Context Decay Verification:**
   - Execute \`osteon_get_cdi\` to verify the knowledge repository is clean.
   - If CDI > 0.10, resolve or acknowledge drifted sources before expanding codebase changes.

2. **Single-Owner Knowledge Rule:**
   - Do NOT duplicate architectural decisions or seam contract definitions. Reference them via authoritative aliases or tokens.
   - Any normative claim introduced in documentation or skills MUST carry a resolvable provenance token: \`[src: <token>]\`.

3. **Same-Wave Contract Synchronization:**
   - When modifying an interface, public API, or wire payload, you MUST update the corresponding Seam Contract in \`docs/contracts/\` within the EXACT SAME commit wave.

4. **Constitutional ADR Primacy:**
   - Accepted Architectural Decision Records (\`docs/adr/\`) are binding. If your implementation requires deviating from an accepted ADR, you must amend the ADR or file a superseding proposal first.

CURRENT TASK OBJECTIVE:
${task}

Confirm compliance with these 4 invariants and proceed with your execution plan.`
          }
        }
      ];
    }
  },
  bone_curation_triage: {
    name: 'bone_curation_triage',
    description: 'Autonomous curation triage prompt to guide an agent in resolving detected context decay.',
    arguments: [
      {
        name: 'drift_summary',
        description: 'JSON summary of decayed blocks and changed sources returned by osteon_get_cdi.',
        required: true
      }
    ],
    generate: (args) => {
      return [
        {
          role: 'user',
          content: {
            type: 'text',
            text: `[OSTEON BONE CURATION TRIAGE PROTOCOL]

You have detected Context Decay in the knowledge base:
${args.drift_summary}

Execute the Three-Tier Policy Resolution Engine:
- **Tier 1 (Non-Functional Auto-Advance):** If source diff is comments/whitespace/internal renaming, approve auto-advance.
- **Tier 2 (Contract-Verified Update):** If code behavior remains 100% compliant with registered seam contracts, synthesize updated attestation and re-anchor.
- **Tier 3 (Quarantine & Asynchronous Escalation):** If a breaking change occurred, mark fact as quarantined without blocking downstream workers, and emit an escalation record.

Generate your structured curation proposals now.`
          }
        }
      ];
    }
  }
};
