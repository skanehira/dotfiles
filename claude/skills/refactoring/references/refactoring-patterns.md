# Refactoring Patterns Reference

Comprehensive catalog of refactoring patterns based on Martin Fowler's "Refactoring" and other sources.

## Code Smells Detection

### Bloaters
- **Long Method**: Methods longer than 20-30 lines
- **Large Class**: Classes with too many fields/methods
- **Primitive Obsession**: Overuse of primitives instead of small objects
- **Long Parameter List**: More than 3-4 parameters
- **Data Clumps**: Same group of data appearing together

### Object-Orientation Abusers
- **Switch Statements**: Complex switch/if-else chains
- **Temporary Field**: Fields only used in certain circumstances
- **Refused Bequest**: Subclass doesn't use inherited methods
- **Alternative Classes with Different Interfaces**: Classes with similar responsibilities but different interfaces

### Change Preventers
- **Divergent Change**: One class commonly changed for different reasons
- **Shotgun Surgery**: Making a change requires many small changes across classes
- **Parallel Inheritance Hierarchies**: Creating subclass requires creating another subclass

### Dispensables
- **Comments**: Explaining what code does (code should be self-explanatory)
- **Duplicate Code**: Same code structure in multiple places
- **Lazy Class**: Class that doesn't do enough to justify existence
- **Dead Code**: Unused code, variables, parameters
- **Speculative Generality**: Code for future features that may never happen

### Couplers
- **Feature Envy**: Method uses more features of another class than its own
- **Inappropriate Intimacy**: Classes know too much about each other's internals
- **Message Chains**: client.getA().getB().getC()
- **Middle Man**: Class delegates most work to another class

## Composing Methods

### Extract Method
**Smell**: Long method, code needs commenting
**Fix**: Turn code fragment into separate method

```javascript
// Before
function printOwing() {
  printBanner();

  console.log("name: " + name);
  console.log("amount: " + getOutstanding());
}

// After
function printOwing() {
  printBanner();
  printDetails(getOutstanding());
}

function printDetails(outstanding) {
  console.log("name: " + name);
  console.log("amount: " + outstanding);
}
```

### Inline Method
**Smell**: Method body as clear as method name
**Fix**: Put method body directly where method is called

```javascript
// Before
function getRating() {
  return moreThanFiveLateDeliveries() ? 2 : 1;
}

function moreThanFiveLateDeliveries() {
  return numberOfLateDeliveries > 5;
}

// After
function getRating() {
  return numberOfLateDeliveries > 5 ? 2 : 1;
}
```

### Extract Variable
**Smell**: Complex expression hard to understand
**Fix**: Put result of expression in well-named variable

```javascript
// Before
if ((platform.toUpperCase().includes("MAC")) &&
    (browser.toUpperCase().includes("IE")) &&
    wasInitialized() && resize > 0) {
  // do something
}

// After
const isMacOs = platform.toUpperCase().includes("MAC");
const isIE = browser.toUpperCase().includes("IE");
const wasResized = resize > 0;

if (isMacOs && isIE && wasInitialized() && wasResized) {
  // do something
}
```

### Inline Variable
**Smell**: Variable name doesn't provide more clarity than expression
**Fix**: Replace variable references with expression

```javascript
// Before
const basePrice = order.basePrice;
return basePrice > 1000;

// After
return order.basePrice > 1000;
```

### Replace Temp with Query
**Smell**: Temporary variable holds result of expression
**Fix**: Extract expression to method, replace temp with method calls

```javascript
// Before
const basePrice = quantity * itemPrice;
if (basePrice > 1000) {
  return basePrice * 0.95;
} else {
  return basePrice * 0.98;
}

// After
function basePrice() {
  return quantity * itemPrice;
}

if (basePrice() > 1000) {
  return basePrice() * 0.95;
} else {
  return basePrice() * 0.98;
}
```

### Split Temporary Variable
**Smell**: Temporary variable assigned more than once (not loop variable)
**Fix**: Use separate variable for each assignment

```javascript
// Before
let temp = 2 * (height + width);
console.log(temp);
temp = height * width;
console.log(temp);

// After
const perimeter = 2 * (height + width);
console.log(perimeter);
const area = height * width;
console.log(area);
```

## Moving Features Between Objects

### Move Method
**Smell**: Method used more by another class than its own
**Fix**: Create new method in class that uses it most

### Move Field
**Smell**: Field used more by another class
**Fix**: Create field in target class, redirect all users

### Extract Class
**Smell**: Class doing work of two classes
**Fix**: Create new class, move relevant fields/methods

```python
# Before
class Person:
    def __init__(self):
        self.name = ""
        self.office_area_code = ""
        self.office_number = ""

    def get_telephone_number(self):
        return f"({self.office_area_code}) {self.office_number}"

# After
class Person:
    def __init__(self):
        self.name = ""
        self.office_telephone = TelephoneNumber()

    def get_telephone_number(self):
        return self.office_telephone.get_telephone_number()

class TelephoneNumber:
    def __init__(self):
        self.area_code = ""
        self.number = ""

    def get_telephone_number(self):
        return f"({self.area_code}) {self.number}"
```

### Inline Class
**Smell**: Class not doing much
**Fix**: Move all features to another class, delete original

### Hide Delegate
**Smell**: Client calls delegate class of server object
**Fix**: Create methods on server to hide delegate

```javascript
// Before
manager = john.department.manager;

// After
manager = john.getManager();

class Person {
  getManager() {
    return this.department.manager;
  }
}
```

## Organizing Data

### Replace Magic Number with Symbolic Constant
```javascript
// Before
function potentialEnergy(mass, height) {
  return mass * height * 9.81;
}

// After
const GRAVITATIONAL_CONSTANT = 9.81;

function potentialEnergy(mass, height) {
  return mass * height * GRAVITATIONAL_CONSTANT;
}
```

### Encapsulate Field
```java
// Before
public String name;

// After
private String name;

public String getName() {
  return name;
}

public void setName(String name) {
  this.name = name;
}
```

### Replace Array with Object
```javascript
// Before
const row = [];
row[0] = "Liverpool";
row[1] = "15";

// After
class Performance {
  constructor(name, wins) {
    this.name = name;
    this.wins = wins;
  }
}

const row = new Performance("Liverpool", "15");
```

## Simplifying Conditional Expressions

### Decompose Conditional
```javascript
// Before
if (date.before(SUMMER_START) || date.after(SUMMER_END)) {
  charge = quantity * winterRate + winterServiceCharge;
} else {
  charge = quantity * summerRate;
}

// After
if (isSummer(date)) {
  charge = summerCharge(quantity);
} else {
  charge = winterCharge(quantity);
}
```

### Consolidate Conditional Expression
```javascript
// Before
function disabilityAmount() {
  if (seniority < 2) return 0;
  if (monthsDisabled > 12) return 0;
  if (isPartTime) return 0;
  // compute disability amount
}

// After
function disabilityAmount() {
  if (isNotEligibleForDisability()) return 0;
  // compute disability amount
}

function isNotEligibleForDisability() {
  return seniority < 2 || monthsDisabled > 12 || isPartTime;
}
```

### Replace Nested Conditional with Guard Clauses
```javascript
// Before
function getPayAmount() {
  if (isDead) {
    result = deadAmount();
  } else {
    if (isSeparated) {
      result = separatedAmount();
    } else {
      if (isRetired) {
        result = retiredAmount();
      } else {
        result = normalPayAmount();
      }
    }
  }
  return result;
}

// After
function getPayAmount() {
  if (isDead) return deadAmount();
  if (isSeparated) return separatedAmount();
  if (isRetired) return retiredAmount();
  return normalPayAmount();
}
```

### Replace Conditional with Polymorphism
```javascript
// Before
class Bird {
  getSpeed() {
    switch (this.type) {
      case EUROPEAN:
        return this.getBaseSpeed();
      case AFRICAN:
        return this.getBaseSpeed() - this.getLoadFactor();
      case NORWEGIAN_BLUE:
        return (this.isNailed) ? 0 : this.getBaseSpeed();
    }
  }
}

// After
class Bird {
  getSpeed() {
    return this.getBaseSpeed();
  }
}

class European extends Bird {
  // inherits getSpeed()
}

class African extends Bird {
  getSpeed() {
    return this.getBaseSpeed() - this.getLoadFactor();
  }
}

class NorwegianBlue extends Bird {
  getSpeed() {
    return (this.isNailed) ? 0 : this.getBaseSpeed();
  }
}
```

## Simplifying Method Calls

### Rename Method
Make method name reveal its intent

### Add Parameter / Remove Parameter
Add or remove parameters as needed for method to get necessary information

### Separate Query from Modifier
Method returns value AND changes object state → split into two methods

```javascript
// Before
function getTotalOutstandingAndSetReadyForSummaries() {
  // ...
}

// After
function getTotalOutstanding() {
  // ...
}

function setReadyForSummaries() {
  // ...
}
```

### Parameterize Method
Several methods do similar things but with different values embedded → use one method with parameter

```javascript
// Before
function fivePercentRaise() {
  salary *= 1.05;
}

function tenPercentRaise() {
  salary *= 1.10;
}

// After
function raise(percentage) {
  salary *= (1 + percentage / 100);
}
```

### Replace Parameter with Explicit Methods
Method runs different code based on parameter value → create separate method for each parameter value

```javascript
// Before
function setValue(name, value) {
  if (name === "height") {
    height = value;
    return;
  }
  if (name === "width") {
    width = value;
    return;
  }
}

// After
function setHeight(value) {
  height = value;
}

function setWidth(value) {
  width = value;
}
```

### Preserve Whole Object
Getting several values from object and passing as parameters → pass whole object instead

```javascript
// Before
const low = daysTempRange.getLow();
const high = daysTempRange.getHigh();
const withinPlan = plan.withinRange(low, high);

// After
const withinPlan = plan.withinRange(daysTempRange);
```

## Anti-Patterns to Avoid

### 1. Premature Optimization
Don't refactor for performance without measuring first

### 2. Gold Plating
Don't add features/flexibility not currently needed

### 3. Refactoring and Behavior Change Together
NEVER mix refactoring with behavior changes in same commit

### 4. Big Bang Refactoring
Don't try to refactor everything at once - incremental is better

### 5. Refactoring Without Tests
ALWAYS ensure tests pass before and after refactoring

## Refactoring Safety Net

### Before Refactoring
1. Ensure comprehensive test coverage
2. All tests passing
3. Commit current changes
4. Have clear goal for refactoring

### During Refactoring
1. Small steps
2. Run tests frequently
3. Keep tests passing
4. Commit frequently

### After Refactoring
1. All tests still pass
2. Code review
3. Verify behavior unchanged
4. Document if necessary

## Resources

### Books
- "Refactoring: Improving the Design of Existing Code" - Martin Fowler
- "Working Effectively with Legacy Code" - Michael Feathers
- "Clean Code" - Robert C. Martin

### Online Resources
- Refactoring.com - Martin Fowler's refactoring catalog
- SourceMaking.com - Refactoring patterns and code smells
- Refactoring.guru - Visual refactoring guide
