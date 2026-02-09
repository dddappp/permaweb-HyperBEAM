# AO/HyperBEAM 开发文档索引

> 本索引按难度从浅到深排序，方便开发者逐步深入学习。

---

## 入门篇（适合初学者）

### dev_aojs-development-guide.md

**难度**：⭐（入门级）

**描述**：AO JavaScript 设备（dev_aojs）开发完整教程，面向入门级开发者

**主要内容**：
- 系统架构概览和 dev_aojs 定位
- 核心概念体系（M1/M2 消息、前缀机制等）
- 开发环境配置和验证
- 四个核心 API 详解（info、init、compute、snapshot、normalize）
- Erlang 与 WASM 通信机制
- 确定性运行时实现原理
- Outbox 消息传递机制
- 状态持久化机制
- 调试技巧和 EUnit 测试
- 部署配置和监控运维
- JavaScript 合约开发最佳实践

**适用读者**：AO 设备开发入门者

---

## 进阶篇（适合有基础的开发者）

### device-collaboration.md

**难度**：⭐⭐（进阶级）

**描述**：设备协作机制文档

**主要内容**：
- 设备栈（Device Stack）的组成和工作原理
- 设备间消息传递
- 设备前缀和数据隔离
- 设备组合和配置

---

### ao-device-state-persistence-verification.md

**难度**：⭐⭐（进阶级）

**描述**：AO 设备状态持久化验证指南

**主要内容**：
- 状态持久化的基本原理
- 不同持久化模式的对比
- 验证状态正确性的方法
- 常见问题和解决方案

---

## 高级篇（适合深入研究的开发者）

### device-configuration-persistence.md

**难度**：⭐⭐⭐（高级）

**描述**：设备配置持久化指南

**主要内容**：
- 设备配置的保存方法
- 配置恢复机制
- 配置版本管理
- 最佳实践建议

---

### quickjs-wasm-compilation-guide.md

**难度**：⭐⭐⭐⭐（专家级）

**描述**：QuickJS WebAssembly 编译指南

**主要内容**：
- QuickJS WASM 编译环境搭建
- 编译参数配置
- WASM 模块构建流程
- 测试和验证方法

---

## 学习路径建议

1. **第一步**：阅读 [dev_aojs-development-guide.md](dev_aojs-development-guide.md)，建立整体认知
2. **第二步**：学习 [device-collaboration.md](device-collaboration.md)，理解设备如何协作
3. **第三步**：研究 [ao-device-state-persistence-verification.md](ao-device-state-persistence-verification.md)，掌握状态管理
4. **第四步**：参考 [device-configuration-persistence.md](device-configuration-persistence.md)，了解配置持久化
5. **第五步**：深入 [quickjs-wasm-compilation-guide.md](quickjs-wasm-compilation-guide.md)，掌握 WASM 编译

---

**最后更新**：2026-02-09
