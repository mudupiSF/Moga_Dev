# /speckit-wireframe

Generate Figma wireframes from a feature specification for customer sign-off before implementation.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Purpose

This command bridges the gap between specification and implementation by producing visual wireframes that:
- Stakeholders can review and approve before any code is written
- Serve as the visual contract for the feature
- Reduce rework by catching UX issues early
- Provide developers with clear visual targets

## Prerequisites

- Feature spec exists at `specs/<feature>/spec.md`
- Spec includes **Panel / Screen Content** section with field mappings
- Spec includes **Navigation & Interactions** section
- Figma MCP is available and authenticated

> **MANDATORY**: Every wireframe MUST follow the real Salesforce Lightning record-page anatomy
> defined in `.cursor/rules/wireframe-salesforce-anatomy.mdc` (global header → app nav → record
> header with compact-layout highlights → body of standard/custom regions labelled `[Standard: …]`
> / `[LWC: …]`). Use REAL object/field API names from the org — never invent fields.

## Outline

1. **Setup**: Run `.specify/scripts/bash/check-prerequisites.sh --json` to get FEATURE_DIR, or use `$ARGUMENTS` if a specific feature is provided.

2. **Load spec context**: Read `FEATURE_DIR/spec.md` and extract:
   - All screens/panels/tabs defined in **Panel / Screen Content**
   - Navigation flows from **Navigation & Interactions**
   - User stories and their acceptance scenarios
   - Persona capabilities (which roles see what)

3. **Generate screen inventory**: Create a list of screens to wireframe:
   ```
   | Screen ID | Screen Name | Primary User Story | Key Components |
   |-----------|-------------|-------------------|----------------|
   | S01 | [Name] | US1 | [Components] |
   ```

4. **Read Figma skill**: Load `/figma-generate-design` skill from the Figma MCP resources.

5. **For each screen**:
   a. Compose a detailed wireframe prompt including:
      - Screen purpose and context
      - All fields/data to display (from Panel Content)
      - Navigation elements and interactions
      - Persona-specific visibility rules
      - Salesforce Lightning Design System (SLDS) styling
   b. Call the Figma MCP `generate_figma_design` or `use_figma` tool
   c. Capture the Figma link

6. **Generate wireframes.md artifact**: Create `FEATURE_DIR/wireframes.md`:

   ```markdown
   # Wireframes: [FEATURE NAME]

   **Generated**: [DATE]
   **Spec**: [Link to spec.md]
   **Status**: 🟡 Pending Sign-off

   ## Screen Inventory

   | Screen | Figma Link | User Story | Status | Approved By |
   |--------|------------|------------|--------|-------------|
   | [Name] | [Link] | US1 | ⏳ Pending | |

   ## Sign-off Checklist

   - [ ] All screens reviewed by Product Owner
   - [ ] Field placements approved
   - [ ] Navigation flow approved
   - [ ] Mobile responsiveness reviewed (if applicable)
   - [ ] Accessibility considerations noted

   ## Feedback Log

   | Date | Screen | Feedback | Resolution |
   |------|--------|----------|------------|

   ## Sign-off

   **Approved for Implementation**: ☐ Yes / ☐ No
   **Approved By**: _______________
   **Date**: _______________

   ---

   ⚠️ **Do not proceed to `/speckit-plan` until sign-off is complete.**
   ```

7. **Update spec.md**: Add a Wireframes section linking to `wireframes.md`.

## Figma Design Guidelines

When generating wireframes for Salesforce Lightning:

### Layout Principles
- Use **Lightning Record Page** layout patterns (header, sidebar, tabs)
- Follow **SLDS** spacing and typography
- Include standard Lightning components: `lightning-card`, `lightning-datatable`, `lightning-badge`
- Show field labels matching API names from spec

### Screen Types
- **Record Page**: Header + sidebar + tabbed content area
- **List View**: Filters + datatable with actions
- **Modal/Dialog**: Form fields + action buttons
- **Dashboard/Roll-up**: KPI cards + charts + drill-down lists

### Annotations
- Mark required fields with asterisk (*)
- Show persona visibility notes (e.g., "RSM+ only")
- Indicate dynamic elements (e.g., "Shows based on record type")
- Note approval gates and stage transitions

## Completion Report

Output:
- Path to generated `wireframes.md`
- Figma file/frame links for each screen
- Summary of screens generated
- Next steps (share with stakeholders, collect feedback)

## Done When

- [ ] All screens from spec have corresponding Figma wireframes
- [ ] `wireframes.md` created with sign-off checklist
- [ ] Spec updated with Wireframes section link
- [ ] Figma links are accessible and shareable
