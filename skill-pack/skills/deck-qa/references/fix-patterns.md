# Fix patterns: before and after

Real cases from the Fall 2026 QA pass and from the scoped-shrink slides, with the fix that keeps the content.

## 1. Two-column slide with two `###` groups per column, 9 bullets in one column

Before (`cs221-fall26/week3`, "Output - System Models"): left column has `### Types of Models` (5 bullets) and `### Why We Need Them` (4 bullets); right column has two code blocks. Fixed with a 17px scoped shrink.

After (preferred): two slides.

```markdown
# Output - System Models

> Visual representations of system structure and behavior

<div class="two-columns">
<div class="column">

### Types of Models
- **Use case diagrams** - Who uses the system and how
- **Data flow diagrams** - How data moves through the system
- **State diagrams** - System states and transitions
- **Entity-relationship diagrams** - Data structure
- **Sequence diagrams** - Interactions over time

</div>
<div class="column">

### Why We Need Them
- Pictures are easier to understand than text
- Reveal missing requirements
- Communication tool between stakeholders
- Basis for the design phase

</div>
</div>

---

# Output - System Models: Food Delivery Example

<div class="two-columns">
<div class="column">

**Use Case Diagram**:
```text
Customer → Browse Restaurants
Customer → Place Order
Customer → Track Delivery
Restaurant → Update Menu
Driver → Accept Delivery
```

</div>
<div class="column">

**Data Flow**:
```text
Customer → Order → Restaurant
Restaurant → Acceptance → System
System → Assignment → Driver
Driver → Location Updates → Customer
```

</div>
</div>
```

## 2. Five principles on one slide (SOLID e-commerce example)

Before: one slide "Real-World SOLID Example" with five `###` sections and two code blocks, 18px shrink.

After (what the QA pass did): "Real-World SOLID Example: S, O, and L" and "Real-World SOLID Example: I and D". Each keeps at most three `###` and one code block. The shrink was kept at 18px on both; with three `###` and 6 bullets each they fit at 20px too, so remove the `<style scoped>` when you touch them next.

Rule: N sections, at most 3 per slide, titles "Topic: A, B, and C" / "Topic: D and E".

## 3. Practice solution that does not fit

Before: "Practice Exercise 1: Solution" with a 30-line refactored class and the explanation bullets.

After: "Practice Exercise 1: Solution" (the code, at most 25 lines, no bullets) then "Practice Exercise 1: Solution, Continued" (the explanation bullets and the trade-off sentence).

Rule: code on one slide, reasoning on the next. The reasoning slide can carry a 6-line excerpt of the code for reference.

## 4. Long code listing (Array-Based Stack, 25+ lines)

Before: a full class with constructor, destructor, push, pop, top, isEmpty in one block.

After: slide A "Array-Based Stack: Class Skeleton" with the members and constructor (about 12 lines); slide B "Array-Based Stack: Push and Pop" with those two methods (about 14 lines) and one sentence on the amortized cost. Repeated methods get `// ...` placeholders, never a second copy.

## 5. Acceptance-criteria slide: three Given/When/Then examples plus the definition

Before: 16px shrink, definition, four "what they define" bullets, the format block, "why important" bullets, and three numbered examples.

After: slide A "Output - Acceptance Criteria" with the definition, the Given/When/Then format block, and the four "what they define" bullets. Slide B "Acceptance Criteria: Login Example" with the user story line and the three examples as a table (Scenario, Given, When, Then; 3 rows).

## 6. Table with 8 rows

Before: a comparison table with 8 process models.

After: rows 1-4 on "Process Models Compared (1 of 2)", rows 5-8 on "(2 of 2)", the same header row on both, and the "when to choose which" sentence only on the second.

## 7. Right overflow in code

Before: a Python line of 112 characters with an inline comment.

After: the comment moved to its own line above; the call broken after a comma. Marp does not wrap `pre`; 80 columns fit at 20px with the 32px padding.

## 8. Notation reference slides (UML class, sequence, state)

These are the legitimate scoped-shrink cases: one table of notation symbols the students look up, not read. Keep `section { font-size: 17px !important; }`, add `<!-- _footer: "Reference slide" -->`, and do not add a bg image or a second table.
