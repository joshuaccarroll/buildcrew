# Build a New Project

Start the BuildCrew Builder to create a new project from scratch.

This command guides you through:

1. **Product Discovery** - A Senior Product Manager will help you define:
   - Vision and problem statement
   - Target users and their needs
   - Success metrics
   - Phased implementation plan

2. **Design Discovery** (optional) - A Senior UX/UI Designer will help you define:
   - Visual style and color palette
   - User flows and screen layouts
   - Component inventory
   - Accessibility considerations

3. **Backlog Generation** - Converts your plan into executable tasks for `./workflow.sh`

---

## Instructions

Read and execute the builder skill at `.claude/skills/builder/SKILL.md`.

Begin by asking for the project name, then guide through the full builder flow with the Product Manager and (optionally) UX Designer personas.

Output files will be created at the project root:
- `PROJECT_[name].md` - Full project plan
- `DESIGN_[name].md` - Design specification (if UI is needed)
- `BACKLOG.md` - Tasks ready for workflow execution
