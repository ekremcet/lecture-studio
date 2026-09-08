# Examples of the house style

Three real slide ranges. Read them before you write the first block of a new deck. Slide numbers count the front matter fence as separator 1, so "slides 2-6" is the first five content slides.

## A. Software engineering, concept and process slides

Source: `cs221-fall26/week3/week3-slides.md`, slides 2-7 (title through the first concept slides).

```markdown
---

# CS221

## Principles of Software Engineering

### Week 3: Software Process Models

**Instructor:** Jane Doe
**Date:** 12.10.2026

---

# Last Week Recap

### Core Principles We Covered

- **Separation of Concerns** - Divide and conquer complexity
- **Abstraction** - Hide unnecessary details, show what matters
- **Modularity** - Build independent, replaceable components
- **Encapsulation** - Information hiding and data protection
- **DRY Principle** - Don't Repeat Yourself
- **KISS Principle** - Keep It Simple, Stupid
- **SOLID Principles** - Five principles for object-oriented design

### This Week's Focus

**How do we organize and structure the software development process?**

---

<!-- _footer: "" -->
<!-- _header: "" -->
<!-- _paginate: false -->

<style scoped>
p { text-align: center}
h1 {text-align: center; font-size: 72px}
</style>

# What is a Software Process?

---

# Software Process

<div class="two-columns">
<div class="column">

> A **software process** is a set of related activities that leads to the production of a software product

**It's not coding** It's a structured approach to:
- Understanding what to build
- Designing the solution
- Implementing the design
- Verifying it works
- Delivering to users
- Maintaining over time

</div>

<div class="column">

### House Analogy

| Building Software | Building a House |
|------------------|------------------|
| Requirements | What rooms? How many floors? Budget? |
| Design | Architectural blueprints |
| Implementation | Construction work |
| Testing | Building inspection |
| Deployment | Move in |
| Maintenance | Repairs and renovations |

</div>
</div>

---

# Why Do We Need Process Models?

<div class="two-columns">
<div class="column">

### Without a Process Model

❌ No clear roadmap - Teams work without direction
❌ Inconsistent quality - Different standards across projects
❌ Poor communication - Misunderstandings and conflicts
❌ Missed deadlines - No realistic planning
❌ Budget overruns - Uncontrolled scope and costs
❌ Failed projects - High risk of complete failure

</div>
<div class="column">

### With a Process Model

✅ Clear structure and predictability
✅ Better communication and coordination
✅ Risk management and quality assurance
✅ Easier to estimate time and cost
✅ Foundation for improvement
✅ Professional accountability

</div>
</div>

---

# Process Model vs. Process

<div class="two-columns">
<div class="column">

### Process Model

> An **abstract representation** of a process. A template or framework that describes the approach.

**Think of it as**: The recipe or blueprint
**Examples**: Waterfall, Scrum, Kanban

### Process

> The **actual implementation** of a process model in a specific context

**Think of it as**: How you actually cook the recipe
**Examples**: "How we do Scrum at our company"

</div>
<div class="column">

### Cooking Analogy

- **Process Model** = Recipe for chocolate cake (general instructions)
- **Process** = How YOU make chocolate cake (your oven, your ingredients, your timing)
- Two chefs following the same recipe = same process model, different processes


### Key Point
The same process model can be implemented differently in different organizations or projects

</div>
</div>




```

## B. Data structures, interface plus question/answer

Source: `cs231-data-structures-and-algorithms/week3/week3-slides.md`, slides 3-8.

```markdown
---

# Recap: Week 2

## What We Covered

- Abstract Data Types (ADTs)
- List ADT and its implementations
- Array-based lists
- Linked lists (singly, doubly, circular)
- Performance analysis and trade-offs

## Today's Focus

Two more fundamental ADTs that restrict how we access data: **Stack** and **Queue**

---

# The Power of Restrictions

### Why Limit Functionality?

With lists, we could:
- Access any element at any position
- Insert/delete anywhere
- Complete freedom

**But sometimes, restrictions make things:**
- **Simpler** to use
- **Faster** to implement
- **Safer** from errors
- **More intuitive** for specific problems

> Constraints can be liberating

---

# Stack ADT

![bg right contain](assets/stack.png)

## What is a Stack?

A **Stack** is a linear data structure that follows **LIFO** (Last In, First Out) principle:
- The last element added is the first one to be removed
- Access is restricted to one end only (the "top")

Think of it like:
- Stack of plates
- Stack of books
- Browser back button
- Undo/redo functionality

---

# Stack

![bg right contain](assets/stack.png)

**Operations:**
- **Add a plate?** Put it on top (push)
- **Remove a plate?** Take from top (pop)
- **Check top plate?** Look at top (peek/top)

**You cannot:**
- Take a plate from the middle
- Access the bottom plate directly
- Rearrange plates

---

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

---

# Stack Operations

<div class="two-columns">
<div class="column">

## Push Operation

```
Initial:            After push(40):
┌────┐              ┌────┐
│ 30 │ ← top        │ 40 │ ← top (new)
├────┤              ├────┤
│ 20 │              │ 30 │
├────┤              ├────┤
│ 10 │              │ 20 │
└────┘              ├────┤
                    │ 10 │
                    └────┘
```

</div>
<div class="column">

## Pop Operation

```
Initial:            After pop():
┌────┐              
│ 40 │ ← top        
├────┤              ┌────┐
│ 30 │              │ 30 │ ← top
├────┤              ├────┤
│ 20 │              │ 20 │
├────┤              ├────┤
│ 10 │              │ 10 │
└────┘              └────┘
```

</div>
</div>

```

## C. Machine learning, math and bg-image slides

Source: `cs211-intro-to-machine-learning/week3/week3-slides.md`, slides 4-8.

```markdown
---

# The Language of Machine Learning

![bg right contain](assets/matrix-meme.jpg)

Machine learning is, at its core, about manipulating large collections of numbers and linear algebra is the language for doing so efficiently.

- Every dataset is a matrix
- Every model parameter is a vector
- Every prediction is a matrix-vector product.

Without linear algebra, we cannot even _write down_ the algorithms, let alone analyze or optimize them.

---

# The Language of Machine Learning

![bg right contain](assets/matrix-meme.jpg)

- **Data representation** — Every data point is a vector of features; the entire dataset is a matrix $\mathbf{X} \in \mathbb{R}^{N \times D}$
- **Model parameters** — Weights in linear regression, neural networks, and SVMs are all vectors or matrices
- **Computational efficiency** — Matrix operations can be parallelized on GPUs, making them orders of magnitude faster than element-wise loops
- **Dimensionality reduction** — Techniques like PCA and SVD compress data by exploiting the structure of matrices
- **Optimization** — Every gradient calculation in ML is a matrix derivative

> _"Linear algebra is the mathematics of the 21st century."_ — Gilbert Strang

Understanding linear algebra is not just helpful for machine learning, it is absolutely essential.

---

# Where Linear Algebra Appears in ML

| Future Week | Topic               | Linear Algebra Connection                                                           |
| ----------- | ------------------- | ----------------------------------------------------------------------------------- |
| Week 4      | Linear Regression   | Normal equations $\mathbf{w} = (\mathbf{X}^T\mathbf{X})^{-1}\mathbf{X}^T\mathbf{y}$ |
| Week 5      | Logistic Regression | Gradient $\nabla_\mathbf{w} L$ via matrix derivatives                               |
| Week 6      | Regularization      | Ridge adds $\lambda\mathbf{I}$ to ensure invertibility                              |
| Week 9      | LDA                 | Generalized eigenvalue problem on scatter matrices                                  |
| Week 10     | SVM                 | Lagrange multipliers, kernel matrix positive semi-definiteness                      |
| Week 11     | Clustering (GMM)    | Covariance matrices, Mahalanobis distance                                           |
| Week 12     | PCA                 | Eigendecomposition of covariance matrix                                             |

Every algorithm we will study is built on the tools from this week.

---

# What Is a Vector?

A **vector** is an ordered list of numbers.

- In machine learning, vectors represent everything
  - data points, model parameters, predictions, gradients.
- Getting comfortable with vectors is the first step toward fluency in ML.

$$\mathbf{v} = \begin{bmatrix} v_1 \\ v_2 \\ \vdots \\ v_n \end{bmatrix} \in \mathbb{R}^n$$

A vector has three complementary interpretations:

- **Geometric** - An arrow in $n$-dimensional space with a direction and a magnitude
- **Algebraic** - A point (or coordinate) in $\mathbb{R}^n$
- **In ML** - The feature representation of a single data sample

---

# Vectors in ML

### Feature Vector

A house might be represented as a 4-dimensional feature vector:

$$\mathbf{x} = \begin{bmatrix} 120 \\ 3 \\ 2 \\ 15 \end{bmatrix} = \begin{bmatrix} \text{square meters} \\ \text{number of rooms} \\ \text{number of bathrooms} \\ \text{age (years)} \end{bmatrix}$$

### Word Embedding

In NLP, every word is mapped to a dense vector a.k.a the famous _word embedding._

- The word **king** might be represented as:

$$\mathbf{w}_{\text{king}} = \begin{bmatrix} 0.8 \\ -0.2 \\ 0.6 \\ \vdots \end{bmatrix} \in \mathbb{R}^{300}$$

These 300 numbers encode the word's meaning in a way that captures semantic relationships

```
