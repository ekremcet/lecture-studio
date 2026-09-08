# Slide archetypes

Every slide is one of these 15 shapes. Each entry: when to use it, a real snippet (trimmed), the budget for it. The budget score is `words/15 + bullets + codeLines/2 + 6*tables + 4*h3 <= 22`.

## 1. Title

First slide of every deck. Budget: trivial.

```markdown
# CS221

## Principles of Software Engineering

### Week 3: Software Process Models

**Instructor:** Jane Doe
**Date:** 12.10.2026
```

## 2. Recap + today's focus

Slide 2 from week 2 on. At most 6 recap bullets and one focus sentence.

```markdown
# Recap: Week 2

## What We Covered

- Abstract Data Types (ADTs)
- List ADT and its implementations
- Array-based lists
- Linked lists (singly, doubly, circular)
- Performance analysis and trade-offs

## Today's Focus

Two more fundamental ADTs that restrict how we access data: **Stack** and **Queue**
```

## 3. Agenda / learning outcomes

Slide 3. Two columns when there are two parts. At most 8 bullets in total.

```markdown
# Today's Agenda

<div class="two-columns">
<div class="column">

## Fundamentals

- Vectors and vector operations
- Matrices and matrix operations
- Transpose, determinant, inverse

</div>
<div class="column">

## Spectral Methods

- Eigenvalues and eigenvectors
- Eigendecomposition (spectral theorem)
- Where each one shows up later

</div>
</div>
```

## 4. Concept, two columns

The workhorse. Left: definition or concept, right: example or contrast. At most 3 `###` per slide, 6 bullets per column, 120 words.

```markdown
# Software Process vs Process Model

<div class="two-columns">
<div class="column">

### Process Model

> An **abstract representation** of a process. A template that describes the approach.

**Think of it as**: the recipe
**Examples**: Waterfall, Scrum, Kanban

</div>
<div class="column">

### Process

> The **actual implementation** of a process model in a specific context

**Think of it as**: how you actually cook
**Examples**: "How we do Scrum at our company"

</div>
</div>
```

## 5. Concept with background image

A visual on the right (meme, diagram, screenshot), bullets on the left. At most 70 words and 7 bullets when the image takes 50%. Use `bg right:40%` to give text more room.

```markdown
# Why Linear Algebra?

![bg right contain](assets/matrix-meme.jpg)

Machine learning is about manipulating large collections of numbers, and linear algebra is the language for doing so efficiently.

- Every dataset is a matrix
- Every model parameter is a vector
- Every prediction is a matrix-vector product

> _"Linear algebra is the mathematics of the 21st century."_ - Gilbert Strang
```

## 6. Code interface

One code block of at most 18 lines and one bold takeaway. No second block.

```markdown
# Stack ADT: Interface

## Essential Operations

```cpp
class Stack {
public:
    virtual void push(int value) = 0;      // Add to top
    virtual int pop() = 0;                 // Remove from top
    virtual int top() = 0;                 // View top element
    virtual bool isEmpty() = 0;            // Check if empty
    virtual int size() = 0;                // Number of elements
    virtual ~Stack() {}
};
```

**Key Principle:** All operations happen at the **top** only
```

## 7. Good / bad pair

Two columns, `### Do ✅` and `### Don't ❌`, or two code blocks of at most 8 lines each under `### ❌ Before` / `### ✅ After`. At most 6 bullets per column.

```markdown
# Encapsulation Best Practices

<div class="two-columns">
<div class="column">

### Do ✅

- Use `_` prefix for internal attributes
- Provide properties for controlled access
- Validate data in setters
- Keep the public interface minimal
- Return copies of mutable internal data

</div>
<div class="column">

### Don't ❌

- Expose internal implementation details
- Create getters/setters for every attribute
- Use `__` unless you need name mangling
- Let callers mutate internal lists

</div>
</div>
```

## 8. Table comparison

One markdown table, at most 6 body rows and 4 columns, plus one sentence or blockquote that says when to choose which. No second table on the slide.

```markdown
# Where Linear Algebra Appears in ML

| Week | Topic | Linear Algebra Connection |
| --- | --- | --- |
| 4 | Linear Regression | Normal equations $\mathbf{w} = (\mathbf{X}^T\mathbf{X})^{-1}\mathbf{X}^T\mathbf{y}$ |
| 5 | Logistic Regression | Gradients via matrix derivatives |
| 6 | Regularization | Ridge adds $\lambda\mathbf{I}$ for invertibility |
| 9 | LDA | Generalized eigenvalue problem |
| 12 | PCA | Eigendecomposition of the covariance matrix |

Every algorithm we study is built on the tools from this week.
```

## 9. Question then Answer

Two consecutive slides with the same title prefix. The question slide has the code or list and nothing else. The answer slide repeats the code annotated, then the result.

```markdown
# Question - RAM Model Complexity

### How many operations in the function below?

```cpp
int sum(int n) {
    int partialSum = 0;
    for (int i = 1; i <= n; i++) {
        partialSum += i * i * i;
    }
    return partialSum;
}
```

---

# Answer - RAM Model Complexity

```cpp
int sum(int n) {
    int partialSum = 0; ---------------> 1
    for (int i = 1; i <= n; i++) { ----> 2n + 2
        partialSum += i * i * i; ------> 4n
    }
    return partialSum; ----------------> 1
}
```

Total = `6n+4`, so the function is **O(n)**
```

## 10. Practice / Studio

A timebox, a required output, numbered steps (at most 6), and a debrief question. The sample answer goes on the NEXT slide, never on this one. Source footer when adapted.

```markdown
# Practice - Turn a Vague Issue into a Process

## 15 minutes

Issue: **"Make CampusPal event search better."**

1. Write two research questions and name the evidence needed.
2. Propose two solution directions with one trade-off each.
3. Define the implementation boundary and explicit non-goals.
4. Write two acceptance tests and one rollback condition.

**Debrief:** At which stage should an agent stop and request a human decision?

<!-- _footer: "Adapted from [CS146S Fall 2026](https://themodernsoftware.dev/)" -->
```

Studio variant (project teams): `**Timebox:** 10 minutes with your team + 5 minutes review`, `**Output:** A one-page ... suitable for D1.`

## 11. Quote / definition

A blockquote definition or an attributed quote inside a concept slide, or a slide on its own for a strong quote. Attribution with ` - Author`.

```markdown
# What Is a Software Process?

> A **software process** is a set of related activities that leads to the production of a software product

**It's not coding.** It is a structured approach to understanding what to build, building it, and checking it.
```

## 12. Section divider

Between blocks. Preferred form uses the theme class; the scoped form is the historical one and is allowed.

```markdown
<!-- _class: divider -->
<!-- _header: "" -->
<!-- _footer: "" -->
<!-- _paginate: false -->

# Let's Practice
```

Historical form:

```markdown
<!-- _footer: "" -->
<!-- _header: "" -->
<!-- _paginate: false -->

<style scoped>
p { text-align: center}
h1 {text-align: center; font-size: 72px}
</style>

# Let's Practice
```

## 13. Summary / key takeaways

A small table or 4-6 numbered takeaways. One per block is the rule of thumb.

```markdown
# Summary

| Operation     | Time Complexity |
| :------------ | :-------------- |
| **Insert**    | O(log N)        |
| **DeleteMin** | O(log N)        |
| **FindMin**   | O(1)            |
| **buildHeap** | O(N)            |

## Key Takeaways

- **Binary Heaps** are efficient Priority Queue implementations.
- Use **Arrays** for storage (complete tree property).
- **Percolate Up** for insertion, **Percolate Down** for deletion.
```

## 14. Next week preview

Topic, 4-6 bullets, reading assignment.

```markdown
# Next Week Preview

## Week 4: Queue Variations and Strings

We'll explore:
- **Priority queues** in detail
- **Circular buffers** and applications
- **Character arrays** and C-strings
- **Pattern matching** basics

## Reading Assignment

- **Weiss Chapter 3.7**: Queue variations
```

## 15. Thank you / closing

Contact block from the course profile, next class date and topic, optional one-line reminder.

```markdown
<!-- _class: lead -->

# Thank You!

## Contact Information

- **Email:** jane.doe@example.edu
- **Office Hours:** Tuesday 14:00-16:00 - Room F-B21
- **Book a slot before coming:** [Booking Link](https://example.edu/booking)
- **Course Repository:** [GitHub](https://github.com/example/cs221-principles-of-software-engineering)

## Next Class

- **Date:** 19.10.2026
- **Topic:** Agile Methodologies
- **Reading:** Sommerville Ch. 3
```

## Full-bleed image slide (variant of 5)

```markdown
<!-- _footer: "" -->
<!-- _header: "" -->
<!-- _paginate: false -->

![bg contain](assets/principles.png)
```
