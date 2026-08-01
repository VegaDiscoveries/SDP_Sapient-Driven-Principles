# SDP Framework Disclaimer

**Last Updated:** July 31, 2026

This document sets out risk, warranty, and liability disclosures for the Sapient-Driven
Principles (SDP) framework — its documentation, skills, scripts, and workflow templates (the
"Framework") — as maintained by Vega Discoveries, LLC ("Vega Discoveries," "we," "us"). It
applies to the Framework itself, however obtained (cloned, copied, or otherwise distributed or acquired),
and to anyone who uses, runs, or modifies it.

This document supplements, and does not modify, amend, or supersede, the license grant in
[`LICENSE`](LICENSE). Rights to copy, modify, and use the Framework are governed exclusively by
`LICENSE`. If anything here conflicts with `LICENSE` regarding those rights, `LICENSE` controls;
for all other matters — warranty, risk, and liability — this document controls.

## 1. Nature of the Framework

SDP is a governance framework for AI-agent-driven software development. It provides structure,
role isolation, and auditability for AI coding agents —
including an optional, fully unattended dispatch mode.

All Framework documentation, skills, scripts, templates, and other related files are provided for informational and
operational purposes. SDP is designed to reduce known AI-agent failure modes — context drift,
unverified self-review, silent re-attempts, undocumented decisions — but using it does not eliminate AI failure modes or
guarantee that software, or any other output, built with it will be free of bugs, security vulnerabilities, logic
errors, or other defects. You remain responsible for reviewing, testing, and validating all
output the Framework produces or dispatches, including code written or actions taken by AI
agents operating under it.

## 2. No Warranty

To the fullest extent permitted by applicable law, the Framework is provided on an "AS IS" and
"AS AVAILABLE" basis. This is consistent with, and supplements, the warranty disclaimer already
contained in `LICENSE`. Vega Discoveries disclaims all warranties, express or implied, including
implied warranties of merchantability, fitness for a particular purpose, and non-infringement,
and does not warrant that the Framework will operate uninterrupted, error-free, or securely, or
that AI subagents operating under it will produce accurate, reliable, or secure output.

## 3. Limitation of Liability

To the fullest extent permitted by applicable law, in no event will Vega Discoveries, its
affiliates, or its developers be liable for any direct, indirect, incidental, special,
consequential, or punitive damages arising out of or relating to use of the Framework, including
without limitation:

- Data loss, repository corruption, or unintended source-control operations (e.g., overwritten
  branches or history) performed by an AI agent operating under the Framework.
- Financial losses arising from monitored, unmonitored (loop-orchestrated, fully unattended) agent
  execution.
- Cost overruns or excessive usage charges from third-party LLM providers (e.g., Anthropic,
  OpenAI) incurred through any Framework-driven use, dispatch, debugging cycles, or loop execution.
- Downtime, defects, security incidents, or any other known or unknown outcome in software built using the Framework.

## 4. Third-Party Tools and Environments

The Framework depends on external tools and environments it does not control, including Git,
PowerShell (Windows PowerShell 5.1 or PowerShell 7+/`pwsh`), your chosen AI coding agent, and —
where used — the Superpowers plugin ecosystem. Vega Discoveries does not own, maintain, or
accept liability for these third-party tools or environments. Choices you make about their
configuration — including running an AI agent in an unattended or elevated-permission mode — are made entirely at your own risk and remain within your
control, not the Framework's.

## 5. Reducing Risk in Practice

The Framework includes built-in mechanisms intended to reduce, not eliminate, the risk of
unwanted outcomes: a default human-gated dispatch mode, a halt discipline that stops the
workflow on ambiguity rather than guessing, a bounded debugging budget that escalates to a human
rather than looping indefinitely, and a material-decision-escalation rule that blocks unapproved
architectural or dependency changes. See the repo documents (like README.md and .claude files) for Orchestration Modes information and
other supplied files for further details. Enabling unattended dispatch is
a deliberate choice to trade oversight for throughput — review those mechanisms before doing so,
and prefer version control and reversible workflows so agent actions can always be undone.
