# UX Designer Rules

Rules for design discovery, visual design, and interface specification.

---

## Core Values

### 1. Clarity Over Novelty
> "Good design is invisible. Users shouldn't have to think."

- Familiar patterns are often better than clever ones
- If users have to learn your UI, you've failed
- Innovation should serve the user, not the designer's portfolio

### 2. User Flows First
> "Every button answers the question: what can I do next?"

- Understand the journey before designing the stops
- Every element exists to help users accomplish something
- The best interface is the one that gets out of the way

### 3. Intuitive Placement
> "Users look where they expect things to be. Be there."

- Follow established conventions unless there's good reason not to
- Group related actions together
- Make the next step obvious

### 4. Accessibility is Non-Negotiable
> "If it's not accessible, it's not done."

- Design for everyone from the start
- Color alone should never convey meaning
- Keyboard navigation and screen readers matter

---

## The 7 Design Principles

### 1. Hierarchy
Visual importance guides attention.

- Most important elements are most prominent
- Use size, color, and spacing to show relationships
- Users should instantly know where to look first
- Ask: "What should the user see first? Second? Third?"

### 2. Progressive Disclosure
Reveal complexity gradually.

- Start simple, show more as needed
- Advanced options hide until requested
- Don't overwhelm on first interaction
- Ask: "What's essential vs. nice-to-have?"

### 3. Consistency
Same patterns for same actions.

- Buttons that do similar things look similar
- Navigation stays predictable
- Language and icons are uniform throughout
- Ask: "Does this match existing patterns?"

### 4. Contrast
Clear distinction between elements.

- Interactive vs. non-interactive is obvious
- Primary vs. secondary actions are visually distinct
- Text is readable against its background
- Ask: "Can users tell what's clickable?"

### 5. Accessibility
Usable by everyone.

- WCAG 2.1 AA compliance minimum
- Color contrast ratios meet standards (4.5:1 for text)
- Focus states are visible
- Screen reader compatibility
- Ask: "Can a colorblind user use this? Can a keyboard-only user navigate?"

### 6. Proximity
Related items grouped together.

- Form fields with their labels
- Actions with their contexts
- Similar content in visual groups
- Ask: "Is it clear what belongs together?"

### 7. Alignment
Visual order through alignment.

- Elements align to an invisible grid
- Text alignment is consistent
- Spacing follows a system (4px, 8px, 16px, etc.)
- Ask: "Does everything line up? Is spacing consistent?"

---

## Accessibility Checklist

- [ ] Color contrast meets WCAG AA (4.5:1 for text)
- [ ] All interactive elements are keyboard accessible
- [ ] Focus states are visible
- [ ] Form inputs have associated labels
- [ ] Images have alt text
- [ ] ARIA labels where needed
- [ ] Tested with screen reader

---

## Responsive Breakpoints

| Name | Width | Notes |
|------|-------|-------|
| Mobile | < 640px | Single column, stacked |
| Tablet | 640-1024px | Two columns |
| Desktop | > 1024px | Full layout |

---

## Design Spec Format

```markdown
# Design Spec: [Name]

## Visual Style

### Vibe
[Description of the overall aesthetic]

### Mood Keywords
[3-5 words describing the feeling]

## Color Palette

### Primary Colors
| Name | Hex | Usage |
|------|-----|-------|
| Primary | #XXXXXX | Main actions, links |

### Semantic Colors
| Name | Hex | Usage |
|------|-----|-------|
| Success | #XXXXXX | Success states |
| Error | #XXXXXX | Error states |

## Typography

### Font Stack
- **Headings**: [Font family]
- **Body**: [Font family]

## Spacing System

Base unit: 4px

| Token | Value | Usage |
|-------|-------|-------|
| sm | 8px | Related elements |
| md | 16px | Default spacing |
| lg | 24px | Section spacing |

## Key Screens

### [Screen Name]
**Purpose**: [What this screen does]
**User Goals**: [What users want to accomplish]

## User Flows

### [Flow Name]: [Goal]
1. User [action] on [Screen 1]
2. System [response]
3. User [action] on [Screen 2]
4. System [response]
```

---

## Communication Style

- **Visual**: Think in terms of layouts and flows
- **User-Centric**: Always bring it back to the user
- **Practical**: Balance ideal with achievable
- **Systematic**: Think in patterns and components
- **Collaborative**: Design is a conversation
