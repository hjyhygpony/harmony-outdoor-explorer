/**
 * 户外群组实时位置同步服务
 * 使用 WebSocket 实现多设备实时通信
 */

const WebSocket = require('ws');
const { randomUUID } = require('crypto');

function uuidv4() {
  return randomUUID();
}

const PORT = 8080;
const wss = new WebSocket.Server({ port: PORT });

// 数据存储
const groups = new Map();      // groupCode -> Group
const clients = new Map();     // odId -> Client
const userGroups = new Map();  // odId -> Set<groupCode>

/**
 * 群组结构
 * {
 *   code: string,
 *   name: string,
 *   ownerId: string,
 *   members: Map<odId, Member>,
 *   geofences: Array<Geofence>,
 *   createTime: number
 * }
 */

/**
 * 成员结构
 * {
 *   odId: string,
 *   name: string,
 *   role: number,  // 0-admin, 1-member
 *   latitude: number,
 *   longitude: number,
 *   battery: number,
 *   signal: number,
 *   lastUpdate: number,
 *   shareExpireTime: number
 * }
 */

// 生成6位群组码
function generateGroupCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return groups.has(code) ? generateGroupCode() : code;
}

// 广播消息给群组所有成员
function broadcastToGroup(groupCode, message, excludeOdId = null) {
  const group = groups.get(groupCode);
  if (!group) return;

  const msgStr = JSON.stringify(message);
  group.members.forEach((member, odId) => {
    if (odId !== excludeOdId) {
      const client = clients.get(odId);
      if (client && client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(msgStr);
      }
    }
  });
}

// 发送消息给单个客户端
function sendToClient(odId, message) {
  const client = clients.get(odId);
  if (client && client.ws.readyState === WebSocket.OPEN) {
    client.ws.send(JSON.stringify(message));
  }
}

wss.on('connection', (ws) => {
  let currentOdId = null;

  console.log('[Server] New connection');

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      console.log('[Server] Received:', msg.type, msg.odId || '');

      switch (msg.type) {
        case 'register':
          handleRegister(ws, msg);
          currentOdId = msg.odId;
          break;
        case 'createGroup':
          handleCreateGroup(msg);
          break;
        case 'joinGroup':
          handleJoinGroup(msg);
          break;
        case 'leaveGroup':
          handleLeaveGroup(msg);
          break;
        case 'updateLocation':
          handleUpdateLocation(msg);
          break;
        case 'updateStatus':
          handleUpdateStatus(msg);
          break;
        case 'sos':
          handleSOS(msg);
          break;
        case 'getGroupInfo':
          handleGetGroupInfo(msg);
          break;
        case 'kickMember':
          handleKickMember(msg);
          break;
        case 'addGeofence':
          handleAddGeofence(msg);
          break;
        case 'addGroupGeofence':
          handleAddGroupGeofence(msg);
          break;
        case 'removeGroupGeofence':
          handleRemoveGroupGeofence(msg);
          break;
        case 'geofenceEvent':
          handleGeofenceEvent(msg);
          break;
        case 'startSharing':
          handleStartSharing(msg);
          break;
        case 'stopSharing':
          handleStopSharing(msg);
          break;
        default:
          console.log('[Server] Unknown message type:', msg.type);
      }
    } catch (e) {
      console.error('[Server] Parse error:', e.message);
    }
  });

  ws.on('close', () => {
    console.log('[Server] Connection closed:', currentOdId);
    if (currentOdId) {
      // 通知所有群组该用户离线
      const userGroupSet = userGroups.get(currentOdId);
      if (userGroupSet) {
        userGroupSet.forEach(groupCode => {
          broadcastToGroup(groupCode, {
            type: 'memberOffline',
            odId: currentOdId
          }, currentOdId);
        });
      }
      clients.delete(currentOdId);
    }
  });

  ws.on('error', (err) => {
    console.error('[Server] WebSocket error:', err.message);
  });
});


// ========== 消息处理函数 ==========

//用户注册
function handleRegister(ws, msg) {
  const { odId, name } = msg;
  
  clients.set(odId, {
    ws,
    name,
    odId,
    connectTime: Date.now()
  });

  if (!userGroups.has(odId)) {
    userGroups.set(odId, new Set());
  }

  // 返回用户已加入的群组列表
  const myGroups = [];
  userGroups.get(odId).forEach(groupCode => {
    const group = groups.get(groupCode);
    if (group) {
      myGroups.push({
        code: group.code,
        name: group.name,
        memberCount: group.members.size,
        isOwner: group.ownerId === odId
      });
    }
  });

  sendToClient(odId, {
    type: 'registerSuccess',
    groups: myGroups
  });

  console.log(`[Server] User registered: ${name} (${odId})`);
}

//创建群组
function handleCreateGroup(msg) {
  const { odId, name, groupName } = msg;
  
  const code = generateGroupCode();
  const group = {
    code,
    name: groupName,
    ownerId: odId,
    members: new Map(),
    geofences: [],
    createTime: Date.now()
  };

  // 创建者自动加入
  group.members.set(odId, {
    odId,
    name,
    role: 0, // admin
    latitude: 0,
    longitude: 0,
    battery: 100,
    signal: 4,
    lastUpdate: Date.now(),
    shareExpireTime: 0
  });

  groups.set(code, group);
  userGroups.get(odId)?.add(code);

  sendToClient(odId, {
    type: 'createGroupSuccess',
    group: {
      code,
      name: groupName,
      memberCount: 1,
      isOwner: true
    }
  });

  console.log(`[Server] Group created: ${groupName} (${code}) by ${name}`);
}

//加入群组
function handleJoinGroup(msg) {
  const { odId, name, groupCode } = msg;
  
  const group = groups.get(groupCode);
  if (!group) {
    sendToClient(odId, {
      type: 'joinGroupFailed',
      reason: '群组不存在'
    });
    return;
  }

  if (group.members.has(odId)) {
    sendToClient(odId, {
      type: 'joinGroupFailed',
      reason: '已在群组中'
    });
    return;
  }

  // 添加成员
  group.members.set(odId, {
    odId,
    name,
    role: 1, // member
    latitude: 0,
    longitude: 0,
    battery: 100,
    signal: 4,
    lastUpdate: Date.now(),
    shareExpireTime: 0
  });

  userGroups.get(odId)?.add(groupCode);

  // 通知加入者
  sendToClient(odId, {
    type: 'joinGroupSuccess',
    group: {
      code: group.code,
      name: group.name,
      memberCount: group.members.size,
      isOwner: false
    }
  });

  // 通知群组其他成员
  broadcastToGroup(groupCode, {
    type: 'memberJoined',
    groupCode,
    member: {
      odId,
      name,
      role: 1
    }
  }, odId);

  console.log(`[Server] ${name} joined group ${groupCode}`);
}

//离开群组
function handleLeaveGroup(msg) {
  const { odId, groupCode } = msg;
  
  const group = groups.get(groupCode);
  if (!group) return;

  const member = group.members.get(odId);
  if (!member) return;

  group.members.delete(odId);
  userGroups.get(odId)?.delete(groupCode);

  // 如果是群主离开，解散群组
  if (group.ownerId === odId) {
    // 通知所有成员群组已解散
    broadcastToGroup(groupCode, {
      type: 'groupDisbanded',
      groupCode
    });
    groups.delete(groupCode);
    console.log(`[Server] Group ${groupCode} disbanded`);
  } else {
    // 通知其他成员
    broadcastToGroup(groupCode, {
      type: 'memberLeft',
      groupCode,
      odId,
      name: member.name
    });
  }

  sendToClient(odId, {
    type: 'leaveGroupSuccess',
    groupCode
  });
}

//更新位置
function handleUpdateLocation(msg) {
  const { odId, groupCode, latitude, longitude, battery, signal, shareExpireTime } = msg;
  
  const group = groups.get(groupCode);
  if (!group) return;

  const member = group.members.get(odId);
  if (!member) return;

  // 检查共享是否过期
  if (member.shareExpireTime > 0 && Date.now() > member.shareExpireTime) {
    // 共享已过期，通知客户端并停止广播
    sendToClient(odId, {
      type: 'shareExpired',
      groupCode
    });
    
    // 清除共享状态
    member.isSharing = false;
    
    // 通知其他成员该用户共享已停止
    broadcastToGroup(groupCode, {
      type: 'memberSharingStopped',
      groupCode,
      odId,
      name: member.name,
      reason: 'expired'
    }, odId);
    
    console.log(`[Server] Share expired for ${member.name} in ${groupCode}`);
    return; // 不更新位置
  }

  member.latitude = latitude;
  member.longitude = longitude;
  member.battery = battery || member.battery;
  member.signal = signal || member.signal;
  member.lastUpdate = Date.now();
  if (shareExpireTime !== undefined) {
    member.shareExpireTime = shareExpireTime;
  }

  // 广播位置更新给其他成员
  broadcastToGroup(groupCode, {
    type: 'locationUpdate',
    groupCode,
    member: {
      odId: member.odId,
      name: member.name,
      latitude: member.latitude,
      longitude: member.longitude,
      battery: member.battery,
      signal: member.signal,
      lastUpdate: member.lastUpdate
    }
  }, odId);
}

//更新状态
function handleUpdateStatus(msg) {
  const { odId, groupCode, battery, signal } = msg;
  
  const group = groups.get(groupCode);
  if (!group) return;

  const member = group.members.get(odId);
  if (!member) return;

  member.battery = battery;
  member.signal = signal;
  member.lastUpdate = Date.now();

  broadcastToGroup(groupCode, {
    type: 'statusUpdate',
    groupCode,
    odId,
    battery,
    signal,
    lastUpdate: member.lastUpdate
  }, odId);
}

//处理sos
function handleSOS(msg) {
  const { odId, groupCode, latitude, longitude, battery, message, recentTrack } = msg;
  
  const group = groups.get(groupCode);
  if (!group) return;

  const member = group.members.get(odId);
  if (!member) return;

  // 广播SOS给所有成员
  broadcastToGroup(groupCode, {
    type: 'sosAlert',
    groupCode,
    from: {
      odId,
      name: member.name
    },
    location: { latitude, longitude },
    battery,
    message,
    recentTrack,
    timestamp: Date.now()
  });

  console.log(`[Server] SOS from ${member.name} in group ${groupCode}`);
}


function handleGetGroupInfo(msg) {
  const { odId, groupCode } = msg;
  
  const group = groups.get(groupCode);
  if (!group) {
    sendToClient(odId, {
      type: 'groupInfo',
      groupCode,
      error: '群组不存在'
    });
    return;
  }

  const members = [];
  group.members.forEach((m) => {
    members.push({
      odId: m.odId,
      name: m.name,
      role: m.role,
      latitude: m.latitude,
      longitude: m.longitude,
      battery: m.battery,
      signal: m.signal,
      lastUpdate: m.lastUpdate,
      isOnline: clients.has(m.odId)
    });
  });

  sendToClient(odId, {
    type: 'groupInfo',
    groupCode,
    group: {
      code: group.code,
      name: group.name,
      ownerId: group.ownerId,
      members,
      geofences: group.geofences || [],
      groupGeofences: group.groupGeofences || [],
      createTime: group.createTime
    }
  });
}

function handleKickMember(msg) {
  const { odId, groupCode, targetOdId } = msg;
  
  const group = groups.get(groupCode);
  if (!group) return;

  // 检查权限
  if (group.ownerId !== odId) {
    sendToClient(odId, {
      type: 'kickFailed',
      reason: '没有权限'
    });
    return;
  }

  const targetMember = group.members.get(targetOdId);
  if (!targetMember) return;

  group.members.delete(targetOdId);
  userGroups.get(targetOdId)?.delete(groupCode);

  // 通知被踢者
  sendToClient(targetOdId, {
    type: 'kicked',
    groupCode,
    groupName: group.name
  });

  // 通知其他成员
  broadcastToGroup(groupCode, {
    type: 'memberKicked',
    groupCode,
    odId: targetOdId,
    name: targetMember.name
  });

  console.log(`[Server] ${targetMember.name} kicked from ${groupCode}`);
}

function handleAddGeofence(msg) {
  const { odId, groupCode, geofence } = msg;
  
  const group = groups.get(groupCode);
  if (!group) return;

  // 检查权限
  if (group.ownerId !== odId) {
    sendToClient(odId, {
      type: 'addGeofenceFailed',
      reason: '没有权限'
    });
    return;
  }

  const newFence = {
    id: uuidv4(),
    ...geofence,
    createTime: Date.now()
  };

  group.geofences.push(newFence);

  // 广播给所有成员
  broadcastToGroup(groupCode, {
    type: 'geofenceAdded',
    groupCode,
    geofence: newFence
  });

  console.log(`[Server] Geofence added to ${groupCode}: ${geofence.name}`);
}

/**
 * 处理添加群组围栏
 */
function handleAddGroupGeofence(msg) {
  const { odId, groupCode, geofence } = msg;
  
  const group = groups.get(groupCode);
  if (!group) {
    sendToClient(odId, {
      type: 'addGroupGeofenceFailed',
      groupCode,
      reason: '群组不存在'
    });
    return;
  }

  // 检查权限 - 只有管理员可以添加围栏
  if (group.ownerId !== odId) {
    sendToClient(odId, {
      type: 'addGroupGeofenceFailed',
      groupCode,
      reason: '需要管理员权限'
    });
    return;
  }

  const newFence = {
    id: geofence.id || uuidv4(),
    groupCode,
    name: geofence.name,
    latitude: geofence.latitude,
    longitude: geofence.longitude,
    radius: geofence.radius,
    type: geofence.type || 'safe',
    creatorId: odId,
    createTime: geofence.createTime || Date.now()
  };

  // 添加到群组围栏列表
  if (!group.groupGeofences) {
    group.groupGeofences = [];
  }
  group.groupGeofences.push(newFence);

  // 通知添加者成功
  sendToClient(odId, {
    type: 'addGroupGeofenceSuccess',
    groupCode,
    geofence: newFence
  });

  // 广播给所有成员（包括添加者）
  broadcastToGroup(groupCode, {
    type: 'groupGeofenceAdded',
    groupCode,
    geofence: newFence
  });

  console.log(`[Server] Group geofence added to ${groupCode}: ${newFence.name} (${newFence.id})`);
}

/**
 * 处理删除群组围栏
 */
function handleRemoveGroupGeofence(msg) {
  const { odId, groupCode, fenceId } = msg;
  
  const group = groups.get(groupCode);
  if (!group) {
    sendToClient(odId, {
      type: 'removeGroupGeofenceFailed',
      groupCode,
      reason: '群组不存在'
    });
    return;
  }

  // 检查权限 - 只有管理员可以删除围栏
  if (group.ownerId !== odId) {
    sendToClient(odId, {
      type: 'removeGroupGeofenceFailed',
      groupCode,
      reason: '需要管理员权限'
    });
    return;
  }

  if (!group.groupGeofences) {
    sendToClient(odId, {
      type: 'removeGroupGeofenceFailed',
      groupCode,
      reason: '围栏不存在'
    });
    return;
  }

  // 查找并删除围栏
  const fenceIndex = group.groupGeofences.findIndex(f => f.id === fenceId);
  if (fenceIndex === -1) {
    sendToClient(odId, {
      type: 'removeGroupGeofenceFailed',
      groupCode,
      reason: '围栏不存在'
    });
    return;
  }

  const removedFence = group.groupGeofences.splice(fenceIndex, 1)[0];

  // 通知删除者成功
  sendToClient(odId, {
    type: 'removeGroupGeofenceSuccess',
    groupCode,
    fenceId
  });

  // 广播给所有成员
  broadcastToGroup(groupCode, {
    type: 'groupGeofenceRemoved',
    groupCode,
    fenceId,
    fenceName: removedFence.name
  });

  console.log(`[Server] Group geofence removed from ${groupCode}: ${removedFence.name} (${fenceId})`);
}

/**
 * 处理围栏事件通知
 */
function handleGeofenceEvent(msg) {
  const { odId, groupCode, geofenceEvent } = msg;
  
  const group = groups.get(groupCode);
  if (!group) return;

  const member = group.members.get(odId);
  if (!member) return;

  // 构建完整的事件消息
  const eventMessage = {
    type: 'geofenceEventNotification',
    groupCode,
    event: {
      memberId: geofenceEvent.memberId,
      memberName: geofenceEvent.memberName,
      fenceId: geofenceEvent.fenceId,
      fenceName: geofenceEvent.fenceName,
      event: geofenceEvent.event, // 'enter' or 'leave'
      timestamp: geofenceEvent.timestamp || Date.now()
    }
  };

  // 广播给群组所有成员（包括触发者）
  broadcastToGroup(groupCode, eventMessage);

  console.log(`[Server] Geofence event in ${groupCode}: ${geofenceEvent.memberName} ${geofenceEvent.event} ${geofenceEvent.fenceName}`);
}

/**
 * 处理开始位置共享
 */
function handleStartSharing(msg) {
  const { odId, groupCode, duration, shareExpireTime } = msg;
  
  const group = groups.get(groupCode);
  if (!group) return;

  const member = group.members.get(odId);
  if (!member) return;

  // 更新成员的共享过期时间
  member.shareExpireTime = shareExpireTime || 0;
  member.isSharing = true;
  member.shareStartTime = Date.now();
  member.shareDuration = duration;

  console.log(`[Server] ${member.name} started sharing in ${groupCode}, duration: ${duration}, expires: ${shareExpireTime > 0 ? new Date(shareExpireTime).toISOString() : 'never'}`);

  // 通知群组其他成员
  broadcastToGroup(groupCode, {
    type: 'memberSharingStarted',
    groupCode,
    odId,
    name: member.name,
    shareExpireTime
  }, odId);
}

/**
 * 处理停止位置共享
 */
function handleStopSharing(msg) {
  const { odId, groupCode } = msg;
  
  const group = groups.get(groupCode);
  if (!group) return;

  const member = group.members.get(odId);
  if (!member) return;

  // 清除共享状态
  member.shareExpireTime = 0;
  member.isSharing = false;

  console.log(`[Server] ${member.name} stopped sharing in ${groupCode}`);

  // 通知群组其他成员
  broadcastToGroup(groupCode, {
    type: 'memberSharingStopped',
    groupCode,
    odId,
    name: member.name
  }, odId);
}

// 定期清理过期数据和检查共享过期
setInterval(() => {
  const now = Date.now();
  const timeout = 5 * 60 * 1000; // 5分钟无活动视为离线

  clients.forEach((client, odId) => {
    // 检查WebSocket连接状态
    if (client.ws.readyState !== WebSocket.OPEN) {
      clients.delete(odId);
    }
  });

  // 清理空群组
  groups.forEach((group, code) => {
    if (group.members.size === 0) {
      groups.delete(code);
      console.log(`[Server] Empty group removed: ${code}`);
    }
  });
}, 60000);

// 定期检查位置共享过期（每10秒）
setInterval(() => {
  const now = Date.now();
  
  groups.forEach((group, groupCode) => {
    group.members.forEach((member, odId) => {
      // 检查是否有过期的共享
      if (member.isSharing && member.shareExpireTime > 0 && now > member.shareExpireTime) {
        // 标记为不再共享
        member.isSharing = false;
        
        // 通知该成员共享已过期
        sendToClient(odId, {
          type: 'shareExpired',
          groupCode
        });
        
        // 通知其他成员
        broadcastToGroup(groupCode, {
          type: 'memberSharingStopped',
          groupCode,
          odId,
          name: member.name,
          reason: 'expired'
        }, odId);
        
        console.log(`[Server] Share expired for ${member.name} in ${groupCode} (periodic check)`);
      }
    });
  });
}, 10000);

console.log(`[Server] WebSocket server running on port ${PORT}`);
console.log(`[Server] Connect using: ws://YOUR_IP:${PORT}`);

